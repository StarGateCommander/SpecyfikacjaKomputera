// Specyfikacja komputera - uruchamiacz .exe
// Ma w sobie Specyfikacja-komputera.ps1 (zasob), zapisuje go do %TEMP% i uruchamia w PowerShellu
// z prosba o administratora. Po odmowie UAC uruchamia bez uprawnien (mniej danych o dyskach i TPM).
// Kompilacja: build.cmd

using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Specyfikacja komputera")]
[assembly: AssemblyProduct("Specyfikacja komputera")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        try
        {
            string dir = Path.Combine(Path.GetTempPath(), "SpecyfikacjaKomputera");
            Directory.CreateDirectory(dir);
            string script = Path.Combine(dir, "Specyfikacja-komputera.ps1");
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Specyfikacja-komputera.ps1"))
            using (FileStream f = File.Create(script))
                s.CopyTo(f);

            // Pulpit zalogowanego uzytkownika - po podniesieniu uprawnien na inne konto admina
            // plik i tak ma trafic tutaj.
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Elevated -Desktop \"" + desktop + "\"";
            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");

            try
            {
                Process.Start(new ProcessStartInfo(ps, args) { UseShellExecute = true, Verb = "runas" });
            }
            catch (Win32Exception) // odmowa UAC
            {
                Process.Start(new ProcessStartInfo(ps, args) { UseShellExecute = true });
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Nie udało się uruchomić:\n" + ex.Message, "Specyfikacja komputera",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
