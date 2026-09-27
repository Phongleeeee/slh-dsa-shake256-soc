using System;
using System.IO;
using System.IO.Ports;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Threading.Tasks;

public sealed class SlhFpgaClient : IDisposable {
    SerialPort serial;
    Process mock;
    Stream input, output;
    uint sequence;
    public bool IsMock { get { return mock != null; } }
    public SlhFpgaClient(string port, int baud) {
        serial = new SerialPort(port, baud, Parity.None, 8, StopBits.One);
        try {
            serial.ReadTimeout=1000; serial.WriteTimeout=10000;
            serial.DtrEnable=false; serial.RtsEnable=false; serial.Open();
            System.Threading.Thread.Sleep(500); // Let reset/BSS scrub finish before the first frame.
            serial.DiscardInBuffer(); sequence=(uint)Environment.TickCount;
        } catch { serial.Dispose(); serial=null; throw; }
    }
    public SlhFpgaClient(string executable) {
        mock=new Process(); mock.StartInfo.FileName=executable; mock.StartInfo.Arguments="--wire";
        mock.StartInfo.UseShellExecute=false; mock.StartInfo.CreateNoWindow=true;
        mock.StartInfo.RedirectStandardInput=true; mock.StartInfo.RedirectStandardOutput=true;
        try { mock.Start(); input=mock.StandardOutput.BaseStream; output=mock.StandardInput.BaseStream; }
        catch { mock.Dispose(); mock=null; throw; }
    }
    public static uint U32(byte[] b,int p) { return (uint)b[p]|(uint)b[p+1]<<8|(uint)b[p+2]<<16|(uint)b[p+3]<<24; }
    public static ulong U64(byte[] b,int p) { return (ulong)U32(b,p)|(ulong)U32(b,p+4)<<32; }
    public static void Put32(byte[] b,int p,uint x) { for(int i=0;i<4;i++) b[p+i]=(byte)(x>>(8*i)); }
    public static byte[] Word(uint x) { byte[] b=new byte[4]; Put32(b,0,x); return b; }
    public static byte[] Random(int count) {
        byte[] b=new byte[count]; using(RandomNumberGenerator r=RandomNumberGenerator.Create()) r.GetBytes(b); return b;
    }
    public static uint Crc(uint crc,byte[] b,int offset,int count) {
        for(int i=offset;i<offset+count;i++) { crc^=b[i]; for(int k=0;k<8;k++) crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u); } return crc;
    }
    static byte[] Build(byte op,uint seq,byte status,byte[] payload) {
        if(payload.Length>1024) throw new ArgumentException("Packet exceeds 1024 bytes");
        byte[] frame=new byte[20+payload.Length]; frame[0]=83; frame[1]=76; frame[2]=72; frame[3]=51;
        frame[4]=1; frame[5]=op; frame[6]=status; Put32(frame,8,seq); Put32(frame,12,(uint)payload.Length);
        Buffer.BlockCopy(payload,0,frame,20,payload.Length);
        uint crc=Crc(0xffffffff,frame,0,16); crc=Crc(crc,frame,20,payload.Length)^0xffffffff; Put32(frame,16,crc); return frame;
    }
    byte ReadByte(DateTime deadline) {
        while(DateTime.UtcNow<deadline) {
            if(serial!=null) { try { return (byte)serial.ReadByte(); } catch(TimeoutException) { continue; } }
            byte[] b=new byte[1]; Task<int> t=input.ReadAsync(b,0,1);
            int ms=(int)Math.Min(600000,Math.Max(1,(deadline-DateTime.UtcNow).TotalMilliseconds));
            if(!t.Wait(ms)) throw new TimeoutException("Native test transport timed out");
            if(t.Result!=1) throw new EndOfStreamException("Device/test process disconnected"+(mock.HasExited ? "; native exit "+mock.ExitCode : "")); return b[0];
        }
        throw new TimeoutException("FPGA response timed out; no software fallback was used");
    }
    public byte[] Exchange(byte opcode,byte[] payload) {
        byte[] request=Build(opcode,++sequence,0,payload);
        try { if(serial!=null) serial.Write(request,0,request.Length); else { output.Write(request,0,request.Length); output.Flush(); } }
        finally { Array.Clear(request,0,request.Length); }
        DateTime deadline=DateTime.UtcNow.AddSeconds(opcode==2 || opcode==5 || opcode==7 ? 600 : 15);
        byte[] h=new byte[20]; int matched=0;
        while(matched<4) { byte b=ReadByte(deadline); if(b==(byte)"SLH3"[matched]) h[matched++]=b; else matched=(b==83) ? 1 : 0; }
        for(int i=4;i<20;i++) h[i]=ReadByte(deadline);
        uint n=U32(h,12);
        if(h[4]!=1 || h[5]!=(byte)(opcode|128) || U32(h,8)!=sequence || h[7]!=0 || n>1024)
            throw new InvalidDataException("Wrong protocol/version/opcode/sequence/length");
        byte[] result=new byte[n]; for(int i=0;i<result.Length;i++) result[i]=ReadByte(deadline);
        uint crc=Crc(0xffffffff,h,0,16); crc=Crc(crc,result,0,result.Length)^0xffffffff;
        if(crc!=U32(h,16)) throw new InvalidDataException("Response CRC mismatch");
        if(h[6]!=0) throw new InvalidOperationException("FPGA status "+h[6]+" (1=request,2=state,3=entropy,4=crypto,5=bounds)");
        return result;
    }
    public byte[] Info() {
        byte[] info=Exchange(1,new byte[0]);
        if(info.Length!=28 || U32(info,0)!=0x00030001 || U32(info,4)==0 || U32(info,8)!=16384 ||
           U32(info,12)!=49856 || (U32(info,24)&15)!=15)
            throw new InvalidDataException("Unsupported firmware");
        bool deviceMock=(U32(info,24)&0x80000000u)!=0;
        if(deviceMock!=IsMock) throw new InvalidDataException("Native test backend cannot be presented as FPGA"); return info;
    }
    public byte[] Keygen() {
        byte[] seed=Random(96);
        try { byte[] pk=Exchange(2,seed); if(pk.Length!=64) throw new InvalidDataException("Keygen public key size"); return pk; }
        finally { Array.Clear(seed,0,seed.Length); }
    }
    public byte[] PublicKey() { byte[] pk=Exchange(10,new byte[0]); if(pk.Length!=64) throw new InvalidDataException("Public key size"); return pk; }
    public void SetMode(uint m) { if(m>2) throw new ArgumentException("Mode 0/1/2 only"); Exchange(12,Word(m)); }
    public void UploadMessage(byte[] message,byte[] context) {
        if(message.Length>16384 || context.Length>255) throw new ArgumentException("FPGA pure mode supports message <=16 KiB, context <=255 bytes");
        byte[] begin=new byte[5+context.Length]; Put32(begin,0,(uint)message.Length); begin[4]=(byte)context.Length;
        Buffer.BlockCopy(context,0,begin,5,context.Length); Exchange(3,begin); Chunks(4,message);
    }
    void Chunks(byte op,byte[] data) {
        for(int offset=0;offset<data.Length;offset+=512) {
            int n=Math.Min(512,data.Length-offset); byte[] p=new byte[n+4]; Put32(p,0,(uint)offset);
            Buffer.BlockCopy(data,offset,p,4,n); Exchange(op,p);
        }
    }
    public byte[] Sign() {
        byte[] rnd=Random(32);
        try { return SignWithRandomness(rnd); }
        finally { Array.Clear(rnd,0,rnd.Length); }
    }
    public byte[] SignWithRandomness(byte[] rnd) {
        if(rnd.Length!=32) throw new ArgumentException("Signing randomness must be 32 bytes");
        byte[] answer=Exchange(5,rnd); if(answer.Length!=4 || U32(answer,0)!=49856) throw new InvalidDataException("Signature length");
        byte[] signature=new byte[49856];
        for(int offset=0;offset<signature.Length;offset+=512) {
            int n=Math.Min(512,signature.Length-offset); byte[] p=new byte[8]; Put32(p,0,(uint)offset); Put32(p,4,(uint)n);
            byte[] chunk=Exchange(6,p); if(chunk.Length!=n) throw new InvalidDataException("Short signature chunk");
            Buffer.BlockCopy(chunk,0,signature,offset,n);
        } return signature;
    }
    public bool Verify(byte[] pk,byte[] sig) {
        if(pk.Length!=64 || sig.Length!=49856) throw new ArgumentException("Key/signature length");
        Exchange(8,Word(49856)); Chunks(9,sig); byte[] r=Exchange(7,pk);
        if(r.Length!=4 || U32(r,0)>1) throw new InvalidDataException("Verify response"); return U32(r,0)==1;
    }
    public byte[] Stats() { byte[] b=Exchange(13,new byte[0]); if(b.Length!=40) throw new InvalidDataException("Metrics length"); return b; }
    public void Zeroize() { Exchange(11,new byte[0]); }
    public void Dispose() {
        if(serial!=null) { serial.Dispose(); serial=null; }
        if(mock!=null) { try { output.Close(); if(!mock.WaitForExit(1000)) mock.Kill(); } finally { mock.Dispose(); mock=null; } }
    }
}
