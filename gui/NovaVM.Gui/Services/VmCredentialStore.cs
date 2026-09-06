using System.Runtime.InteropServices;
using System.Text;

namespace NovaVM.Gui.Services;

/// <summary>Enregistre/relit les identifiants Windows d'une VM via le Gestionnaire
/// d'identifiants natif de Windows (Credential Manager), chiffres par DPAPI et lies
/// au compte Windows + a cette machine - visibles et supprimables par l'utilisateur
/// via "Gestionnaire d'identifiants" dans le Panneau de configuration, contrairement
/// a un stockage prive/opaque dans un fichier de config NovaVM.
///
/// Ce n'est PAS le meme mecanisme que le flux "stdin uniquement, jamais stocke" des
/// scripts (voir Fix-NovaVmEnhancedSession.ps1 etc.) : ce store est une commodite
/// opt-in ("Se souvenir de mes identifiants") au niveau de l'interface, avant que
/// les identifiants ne soient transmis au script via stdin comme d'habitude.</summary>
internal static class VmCredentialStore
{
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWrite(ref Credential credential, uint flags);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);

    private static string TargetName(string vmName) => $"NovaVM:VM:{vmName}";

    public static void Save(string vmName, string username, string password)
    {
        var passwordBytes = Encoding.Unicode.GetBytes(password);
        var blobPtr = Marshal.AllocHGlobal(passwordBytes.Length);
        try
        {
            Marshal.Copy(passwordBytes, 0, blobPtr, passwordBytes.Length);
            var credential = new Credential
            {
                Type = CredTypeGeneric,
                TargetName = TargetName(vmName),
                Comment = "NovaVM - identifiants Windows de la VM (voir Gestionnaire d'identifiants pour supprimer)",
                CredentialBlobSize = (uint)passwordBytes.Length,
                CredentialBlob = blobPtr,
                Persist = CredPersistLocalMachine,
                UserName = username,
            };

            CredWrite(ref credential, 0);
        }
        finally
        {
            Marshal.FreeHGlobal(blobPtr);
        }
    }

    public static bool TryLoad(string vmName, out string username, out string password)
    {
        username = "";
        password = "";

        if (!CredRead(TargetName(vmName), CredTypeGeneric, 0, out var credentialPtr))
        {
            return false;
        }

        try
        {
            var credential = Marshal.PtrToStructure<Credential>(credentialPtr);
            username = credential.UserName ?? "";
            if (credential.CredentialBlob != IntPtr.Zero && credential.CredentialBlobSize > 0)
            {
                var bytes = new byte[credential.CredentialBlobSize];
                Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
                password = Encoding.Unicode.GetString(bytes);
            }
            return !string.IsNullOrEmpty(username);
        }
        finally
        {
            CredFree(credentialPtr);
        }
    }

    public static void Delete(string vmName)
    {
        CredDelete(TargetName(vmName), CredTypeGeneric, 0);
    }
}
