// CoopRC-Setup.exe: finds Republic Commando, unpacks the embedded CoopRC.zip into <game>\CoopRC and runs
// Install-CoopRC.ps1 from there. Built by make_dist.ps1 with the .NET Framework csc (no runtime to install).
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows.Forms;

static class Setup
{
	const string Title = "CoopRC Setup";

	static string FindGame()
	{
		var steam = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) + @"\Steam";
		var dirs = new System.Collections.Generic.List<string> { steam };
		var vdf = steam + @"\steamapps\libraryfolders.vdf";
		if (File.Exists(vdf))
			foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\""))
				dirs.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
		return dirs.Select(d => d + @"\steamapps\common\Star Wars Republic Commando").FirstOrDefault(IsGame);
	}

	static bool IsGame(string dir) { return File.Exists(dir + @"\GameData\System\System.ini"); }

	[STAThread]
	static int Main()
	{
		var game = FindGame();
		if (game == null || MessageBox.Show("Install CoopRC into\n" + game + "?", Title, MessageBoxButtons.YesNo) == DialogResult.No)
		{
			var pick = new FolderBrowserDialog { Description = "Select your \"Star Wars Republic Commando\" folder" };
			if (pick.ShowDialog() != DialogResult.OK)
				return 1;
			game = pick.SelectedPath;
		}

		if (!IsGame(game))
		{
			MessageBox.Show("That isn't a Republic Commando folder (no GameData\\System\\System.ini).", Title);
			return 1;
		}

		var target = game + @"\CoopRC";
		try
		{
			if (Directory.Exists(target))
				Directory.Delete(target, true);
			using (var zip = new ZipArchive(Assembly.GetExecutingAssembly().GetManifestResourceStream("CoopRC.zip")))
				foreach (var e in zip.Entries.Where(e => e.Name != ""))
				{
					var path = Path.Combine(game, e.FullName.Replace('/', '\\'));
					Directory.CreateDirectory(Path.GetDirectoryName(path));
					e.ExtractToFile(path, true);
				}
		}
		catch (Exception ex)
		{
			MessageBox.Show("Could not unpack into " + target + ":\n" + ex.Message, Title);
			return 1;
		}

		// The script prints progress (the arms build takes about a minute) and pauses on errors.
		var ps = Process.Start(new ProcessStartInfo("powershell.exe",
			"-NoProfile -ExecutionPolicy Bypass -Command \"try { & '" + target + "\\Install-CoopRC.ps1' -GameDir '" + game +
			"' } catch { Write-Host $_ -ForegroundColor Red; pause; exit 1 }\"") { UseShellExecute = false });
		ps.WaitForExit();

		if (ps.ExitCode != 0)
		{
			MessageBox.Show("Install failed, see the PowerShell window for why.", Title);
			return 1;
		}

		MessageBox.Show("CoopRC installed.\n\nHost: " + target + "\\Host-Coop.bat\nJoin: " + target +
			"\\Join-Coop.bat [07|40|62], then right-click the host in Steam > Join Game\n\nSee README.md in that folder.", Title);
		Process.Start("explorer.exe", "\"" + target + "\"");
		return 0;
	}
}
