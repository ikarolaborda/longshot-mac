using Mono.Cecil;
using Mono.Cecil.Cil;

if (args.Length < 2) { Console.Error.WriteLine("usage: ilpatch <Core.dll> <MoltenVK-name>"); return 2; }
string path = args[0];
string vkName = args[1];

var rp = new ReaderParameters { ReadWrite = false, InMemory = true };
using var asm = AssemblyDefinition.ReadAssembly(path, rp);
var mod = asm.MainModule;

// ---------- Patch 1: VulkanRequirements.Read library name ----------
var vulkanReq = mod.GetType("LongshotLauncher.VulkanRequirements") ?? mod.GetTypes().First(t => t.Name == "VulkanRequirements");
var read = vulkanReq.Methods.First(m => m.Name == "Read");
int replaced = 0;
foreach (var ins in read.Body.Instructions)
{
    if (ins.OpCode == OpCodes.Ldstr && (string)ins.Operand == "libvulkan.so.1")
    { ins.Operand = vkName; replaced++; }
}
Console.WriteLine($"[1] VulkanRequirements.Read lib name patched: {replaced}");

// ---------- Patch 2: Requirements.Check - drop X64/Windows/glibc OS gate ----------
var reqs = mod.GetTypes().First(t => t.Name == "SystemRequirements");
var check = reqs.Methods.First(m => m.Name == "Check");
var evaluate = reqs.Methods.First(m => m.Name == "Evaluate");
Console.WriteLine($"[2] Evaluate signature: {evaluate}");

// collect needed callee references from the original body
MethodReference memGb = null, threads = null, freeBytes = null, vkRead = null;
foreach (var ins in check.Body.Instructions)
{
    if (ins.Operand is MethodReference mr)
    {
        if (mr.Name == "MemoryGb" && memGb == null) memGb = mr;
        if (mr.Name == "Threads" && threads == null) threads = mr;
        if (mr.Name == "FreeBytes" && freeBytes == null) freeBytes = mr;
        if (mr.Name == "Read" && vkRead == null) vkRead = mr;
    }
}
Console.WriteLine($"[2] callees: {memGb}, {threads}, {freeBytes}, {vkRead}");
if (memGb == null || threads == null || freeBytes == null || vkRead == null) { Console.Error.WriteLine("callee not found"); return 1; }

var il = check.Body.GetILProcessor();
check.Body.Instructions.Clear();
check.Body.Variables.Clear();
check.Body.ExceptionHandlers.Clear();
il.Emit(OpCodes.Ldc_I4_1);                 // OS requirement: always satisfied (macOS/ARM64 allowed)
il.Emit(OpCodes.Call, memGb);              // SystemInfo.MemoryGb()
il.Emit(OpCodes.Call, threads);            // SystemInfo.Threads()
il.Emit(OpCodes.Ldarg_0);                 // folder
il.Emit(OpCodes.Call, freeBytes);         // Disk.FreeBytes(folder)
il.Emit(OpCodes.Call, vkRead);            // VulkanRequirements.Read()
il.Emit(OpCodes.Call, evaluate);           // Evaluate(...)
il.Emit(OpCodes.Ret);
Console.WriteLine("[2] Requirements.Check rewritten (X64 gate removed)");


// ---------- Patch 3: Vulkan delegate conventions Winapi -> Cdecl ----------
int convFixed = 0;
foreach (var nt in vulkanReq.NestedTypes)
{
    var attrs = nt.CustomAttributes.Where(a => a.AttributeType.Name == "UnmanagedFunctionPointerAttribute").ToList();
    foreach (var a in attrs)
    {
        if (a.ConstructorArguments.Count >= 1)
        {
            var argType = a.ConstructorArguments[0].Type;
            a.ConstructorArguments[0] = new Mono.Cecil.CustomAttributeArgument(argType, 2); // CallingConvention.Cdecl
            convFixed++;
        }
    }
}
Console.WriteLine($"[3] delegate conventions fixed: {convFixed}");


// ---------- Patch 4: request Vulkan 1.3 instance (MoltenVK clamps report to request) ----------
int verFixed = 0;
foreach (var ins in read.Body.Instructions)
{
    if (ins.OpCode.Code == Mono.Cecil.Cil.Code.Ldc_I4 && ins.Operand is int v && v == 4198400)
    { ins.Operand = 4206592; verFixed++; }
}
Console.WriteLine($"[4] apiVersion bumped to 1.3: {verFixed}");


// ---------- Patch 5: mesh-shader detection reflects Metal mesh threads (Apple GPU family 9) ----------
int meshFixed = 0;
{
    var instrs = read.Body.Instructions;
    var ilp = read.Body.GetILProcessor();
    for (int i = 1; i < instrs.Count; i++)
    {
        var ins = instrs[i];
        if (ins.OpCode == Mono.Cecil.Cil.OpCodes.Call && ins.Operand is MethodReference mr && mr.Name == "ReadInt32")
        {
            var prev = instrs[i-1];
            if (prev.OpCode == Mono.Cecil.Cil.OpCodes.Ldc_I4 && prev.Operand is int off && (off == 528 || off == 532))
            {
                ins.OpCode = Mono.Cecil.Cil.OpCodes.Pop;   // pops the offset arg
                ins.Operand = null;
                var p2 = ilp.Create(Mono.Cecil.Cil.OpCodes.Pop);       // pops the buffer ptr
                var c1 = ilp.Create(Mono.Cecil.Cil.OpCodes.Ldc_I4_1);  // push 1 -> feature present
                ilp.InsertAfter(ins, c1);
                ilp.InsertAfter(ins, p2);
                meshFixed++;
            }
        }
    }
}
Console.WriteLine($"[5] mesh-shader reads forced true: {meshFixed}");

asm.Write(path);
Console.WriteLine("written: " + path);
return 0;



