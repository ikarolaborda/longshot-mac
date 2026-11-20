using Microsoft.NET.HostModel.Bundle;
using System.Runtime.InteropServices;

// args: <singlefilehost-template> <outputDir> <filesDir> <entryName>
string hostTemplate = args[0];
string outputDir = args[1];
string filesDir = args[2];
string entryName = args[3];

// 1) Patch the apphost template with the entry assembly binding
string patchedHost = Path.Combine(outputDir, entryName + ".apphost.tmp");
Microsoft.NET.HostModel.AppHost.HostWriter.CreateAppHost(
    hostTemplate,
    patchedHost,
    entryName + ".dll",
    windowsGraphicalUserInterface: false,
    assemblyToCopyResourcesFrom: null,
    enableMacOSCodeSign: true);

// 2) Bundle all files after the patched host
var specs = new List<FileSpec>();
specs.Add(new FileSpec(patchedHost, entryName));
foreach (var f in Directory.GetFiles(filesDir))
{
    var rel = Path.GetFileName(f);
    specs.Add(new FileSpec(f, rel));
}

var bundler = new Bundler(
    entryName,
    outputDir,
    BundleOptions.BundleAllContent | BundleOptions.EnableCompression,
    OSPlatform.OSX,
    Architecture.Arm64,
    new Version(10, 0),
    diagnosticOutput: false,
    appAssemblyName: entryName,
    macosCodesign: true);
string result = bundler.GenerateBundle(specs);
File.Delete(patchedHost);
Console.WriteLine("bundle written: " + result);
