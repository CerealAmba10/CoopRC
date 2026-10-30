param([int]$ProcId, [string]$Out)
# Save a half-size capture of one process's window, even if other windows cover it.
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
public struct RECT { public int L,T,R,B; } }
'@
$hwnd = (Get-Process -Id $ProcId).MainWindowHandle
$r = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
[W]::PrintWindow($hwnd, $dc, 2) | Out-Null   # PW_RENDERFULLCONTENT captures D3D content
$g.ReleaseHdc($dc)
(New-Object System.Drawing.Bitmap($bmp, [int]($w / 2), [int]($h / 2))).Save($Out)
