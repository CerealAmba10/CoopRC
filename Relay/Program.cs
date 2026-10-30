// CoopRelay: carries Republic Commando's UDP game traffic over Steam's peer-to-peer relay, so co-op
// works without port forwarding or a VPN.
//
//   host:   CoopRelay host                      game server stays on UDP 7777; prints your Steam ID
//   join:   CoopRelay join <hostSteamID> [slot]  game client connects to 127.0.0.1:7778 (started for you)
//           CoopRelay join [slot]                waits for Steam "Join Game" on the host (or an invite)
//
// The relay doesn't understand the game protocol: it forwards datagrams. On the host each friend gets
// their own local UDP socket towards 127.0.0.1:7777, so the game sees them as separate clients.
// "--direct <ip:port>" replaces the Steam hop with plain UDP (for testing on one PC).
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using Steamworks;

const int GamePort = 7777;     // RC listen server
const int ClientPort = 7778;   // what the joining game connects to locally
const int DirectPort = 7790;   // --direct test mode: host relay listens here

// Everything printed also goes to CoopRelay-<mode>.log next to the exe, and a failure keeps the window open:
// players start this from a .bat, so otherwise an error closes the window before anyone reads it.
var log = new StreamWriter(Path.Combine(AppContext.BaseDirectory, $"CoopRelay-{(args.Length > 0 ? args[0] : "usage")}.log"), false) { AutoFlush = true };
Console.SetOut(new Tee(Console.Out, log));
Console.WriteLine($"CoopRelay {string.Join(' ', args)}  ({DateTime.Now})");

bool direct = args.Contains("--direct");
int code;

try
{
	code = Run();
}
catch (Exception e)
{
	Console.WriteLine($"Error: {e}");
	code = 1;
}

if (code != 0)
{
	Console.WriteLine($"The relay stopped. Details are in CoopRelay-{(args.Length > 0 ? args[0] : "usage")}.log. Press Enter to close.");
	Console.ReadLine();
}

return code;

int Run()
{
	if (args.Length == 0 || (args[0] != "host" && args[0] != "join"))
	{
		Console.WriteLine("Usage: CoopRelay host [--direct]");
		Console.WriteLine("       CoopRelay join [hostSteamID] [07|40|62] [--nolaunch] [--direct <ip:port>]");
		return 1;
	}

	ITransport transport = direct ? new UdpTransport(args[0] == "host" ? DirectPort : 0) : new SteamTransport();

	if (!transport.Init(out string error))
	{
		Console.WriteLine(error);
		return 1;
	}

	Console.CancelKeyPress += (_, e) => { e.Cancel = true; transport.Shutdown(); Environment.Exit(0); };
	return args[0] == "host" ? Host(transport) : Join(transport, args);
}

int Host(ITransport net)
{
	var peers = new Dictionary<string, UdpClient>(); // remote peer -> socket towards the game server
	var server = new IPEndPoint(IPAddress.Loopback, GamePort);

	Console.WriteLine($"Hosting. Friends join with:  CoopRelay join {net.LocalId}");
	if (net is SteamTransport steam)
	{
		steam.Advertise();
		Console.WriteLine("Or they right-click you in Steam > Join Game (or you right-click them > Invite to Game).");
	}
	Console.WriteLine("Start the game with Host-Coop.bat. Leave this window open while you play.");

	while (true)
	{
		bool busy = false;
		net.Pump();

		while (net.Receive(out string from, out byte[] data))
		{
			if (!peers.TryGetValue(from, out var sock))
			{
				sock = Udp.Open(new IPEndPoint(IPAddress.Loopback, 0));
				sock.Connect(server);
				peers[from] = sock;
				Console.WriteLine($"Friend connected: {net.Describe(from)}");
			}

			sock.Send(data, data.Length);
			busy = true;
		}

		foreach (var (peer, sock) in peers)
		{
			while (Udp.TryReceive(sock, out byte[] data, out _))
			{
				net.Send(peer, data);
				busy = true;
			}
		}

		if (!busy)
			Thread.Sleep(1);
	}
}

int Join(ITransport net, string[] a)
{
	string? host = direct ? a[Array.IndexOf(a, "--direct") + 1] : a.Skip(1).FirstOrDefault(s => s.Length > 4 && ulong.TryParse(s, out _));

	if (host == null)
	{
		if (net is not SteamTransport steam)
			return 1;

		Console.WriteLine("Waiting for you to join the host in Steam: right-click them in your friends list > Join Game,");
		Console.WriteLine("or accept their invite. Leave this window open.");
		host = steam.WaitForJoin();
	}

	string? slot = a.Skip(1).FirstOrDefault(s => s is "07" or "40" or "62");

	if (!net.Connect(host, out string error))
	{
		Console.WriteLine(error);
		return 1;
	}

	UdpClient local;

	try
	{
		local = Udp.Open(new IPEndPoint(IPAddress.Loopback, ClientPort));
	}
	catch (SocketException)
	{
		Console.WriteLine($"Port {ClientPort} is in use: another CoopRelay is probably still running. Close it (or end CoopRelay.exe in Task Manager) and try again.");
		return 1;
	}
	IPEndPoint? game = null;

	Console.WriteLine($"Relaying to host {net.Describe(host)}. Game connects to 127.0.0.1:{ClientPort}.");

	if (!a.Contains("--nolaunch"))
		LaunchGame(slot);

	var waiting = Stopwatch.StartNew();
	bool replied = false, warned = false;

	while (true)
	{
		bool busy = false;
		net.Pump();

		while (Udp.TryReceive(local, out byte[] data, out IPEndPoint? ep))
		{
			game = ep;
			net.Send(host, data);
			busy = true;
		}

		while (net.Receive(out string from, out byte[] data))
		{
			if (from == host && game != null)
				local.Send(data, data.Length, game);

			if (from == host && !replied)
			{
				replied = true;
				Console.WriteLine("Connected: the host's game is answering. You should land in their main menu.");
			}

			busy = true;
		}

		if (!replied && !warned && waiting.Elapsed.TotalSeconds > 20)
		{
			warned = true;
			Console.WriteLine(game == null
				? $"Your game hasn't connected to 127.0.0.1:{ClientPort} yet."
				: "No answer from the host yet. Check they ran Host-Coop.bat and their relay window is open.");
		}

		if (!busy)
			Thread.Sleep(1);
	}
}

void LaunchGame(string? slot)
{
	// The relay ships in <game>\CoopRC\Relay, so the game is two folders up.
	string sys = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "GameData", "System"));
	string exe = Path.Combine(sys, "CT.exe");

	if (!File.Exists(exe))
	{
		Console.WriteLine($"Start the game yourself and connect to 127.0.0.1:{ClientPort} (CT.exe not found at {exe}).");
		return;
	}

	string url = $"127.0.0.1:{ClientPort}" + (slot != null ? $"?CoopSlot={slot}" : "");
	Process.Start(new ProcessStartInfo(exe, $"\"{url}\"") { WorkingDirectory = sys, UseShellExecute = false });
	Console.WriteLine($"Started the game ({url}).");
}

static class Udp
{
	// Windows reports an ICMP "port unreachable" (e.g. the game reopening its socket during a level
	// change) as a reset on the next receive. For a datagram relay that's just a dropped packet.
	const int SIO_UDP_CONNRESET = -1744830452;

	public static UdpClient Open(IPEndPoint bind)
	{
		var sock = new UdpClient(bind);
		sock.Client.IOControl(SIO_UDP_CONNRESET, new byte[] { 0 }, null);
		return sock;
	}

	public static bool TryReceive(UdpClient sock, out byte[] data, out IPEndPoint? from)
	{
		data = Array.Empty<byte>();
		from = null;

		try
		{
			if (sock.Available <= 0)
				return false;

			data = sock.Receive(ref from);
			return true;
		}
		catch (SocketException)
		{
			return false;
		}
	}
}

interface ITransport
{
	string LocalId { get; }
	bool Init(out string error);
	bool Connect(string peer, out string error);
	void Pump();
	bool Receive(out string from, out byte[] data);
	void Send(string to, byte[] data);
	string Describe(string peer);
	void Shutdown();
}

// Steam P2P (ISteamNetworking): NAT punch-through with Steam relay fallback; needs Steam running and
// both players signed in. Republic Commando's app ID (steam_appid.txt = 6000).
class SteamTransport : ITransport
{
	Callback<P2PSessionRequest_t>? sessionRequest;
	Callback<P2PSessionConnectFail_t>? connectFail;
	readonly byte[] buffer = new byte[4096];

	public string LocalId => SteamUser.GetSteamID().m_SteamID.ToString();

	public bool Init(out string error)
	{
		error = "";

		if (!SteamAPI.Init())
		{
			error = "Couldn't start Steam networking. Make sure Steam is running, you're signed in, and you own Republic Commando on Steam (app 6000).";
			return false;
		}

		SteamNetworking.AllowP2PPacketRelay(true);

		// Accept anyone who connects to the host; the game itself decides who gets in.
		sessionRequest = Callback<P2PSessionRequest_t>.Create(r => SteamNetworking.AcceptP2PSessionWithUser(r.m_steamIDRemote));
		connectFail = Callback<P2PSessionConnectFail_t>.Create(f =>
			Console.WriteLine($"Steam connection to {f.m_steamIDRemote} failed (error {f.m_eP2PSessionError})."));

		return true;
	}

	public bool Connect(string peer, out string error)
	{
		error = ulong.TryParse(peer, out _) ? "" : $"'{peer}' isn't a Steam ID (a long number the host's relay prints).";
		return error == "";
	}

	public void Pump() => SteamAPI.RunCallbacks();

	public bool Receive(out string from, out byte[] data)
	{
		from = "";
		data = Array.Empty<byte>();

		if (!SteamNetworking.IsP2PPacketAvailable(out uint size) || size > buffer.Length)
			return false;

		if (!SteamNetworking.ReadP2PPacket(buffer, size, out uint read, out CSteamID remote))
			return false;

		from = remote.m_SteamID.ToString();
		data = buffer.AsSpan(0, (int)read).ToArray();
		return true;
	}

	public void Send(string to, byte[] data) =>
		SteamNetworking.SendP2PPacket(new CSteamID(ulong.Parse(to)), data, (uint)data.Length, EP2PSend.k_EP2PSendUnreliable); // NoDelay drops everything until a session exists, so it never connects

	public string Describe(string peer)
	{
		string name = SteamFriends.GetFriendPersonaName(new CSteamID(ulong.Parse(peer)));
		return string.IsNullOrEmpty(name) ? peer : $"{name} ({peer})";
	}

	public void Shutdown() => SteamAPI.Shutdown();

	// Steam friends list: "connect" rich presence makes Join Game / Invite to Game show up for the host.
	// Steam hands it to the friend's running copy (this relay, app 6000) as a join request.
	public void Advertise()
	{
		SteamFriends.SetRichPresence("status", "Hosting Republic Commando co-op");
		SteamFriends.SetRichPresence("connect", LocalId);
	}

	public string WaitForJoin()
	{
		string? host = null;
		using var join = Callback<GameRichPresenceJoinRequested_t>.Create(r =>
			host = ulong.TryParse(r.m_rgchConnect.Trim(), out _) ? r.m_rgchConnect.Trim() : r.m_steamIDFriend.m_SteamID.ToString());

		while (host == null)
		{
			SteamAPI.RunCallbacks();
			Thread.Sleep(50);
		}

		Console.WriteLine($"Joining {Describe(host)}.");
		return host;
	}
}

// Plain UDP between the two relays, for testing the forwarding on one PC without Steam.
class UdpTransport : ITransport
{
	readonly UdpClient sock;

	public UdpTransport(int port) => sock = Udp.Open(new IPEndPoint(IPAddress.Loopback, port));

	public string LocalId => sock.Client.LocalEndPoint!.ToString()!;
	public bool Init(out string error) { error = ""; return true; }
	public bool Connect(string peer, out string error) { error = IPEndPoint.TryParse(peer, out _) ? "" : $"bad address '{peer}'"; return error == ""; }
	public void Pump() { }

	public bool Receive(out string from, out byte[] data)
	{
		from = "";

		if (!Udp.TryReceive(sock, out data, out IPEndPoint? ep))
			return false;

		from = ep!.ToString();
		return true;
	}

	public void Send(string to, byte[] data) => sock.Send(data, data.Length, IPEndPoint.Parse(to));
	public string Describe(string peer) => peer;
	public void Shutdown() => sock.Close();
}

// Writes to the console and the log file at once.
class Tee : TextWriter
{
	readonly TextWriter a, b;
	public Tee(TextWriter a, TextWriter b) { this.a = a; this.b = b; }
	public override System.Text.Encoding Encoding => a.Encoding;
	public override void Write(char c) { a.Write(c); b.Write(c); }
	public override void Write(string? s) { a.Write(s); b.Write(s); }
	public override void WriteLine(string? s) { a.WriteLine(s); b.WriteLine(s); }
}
