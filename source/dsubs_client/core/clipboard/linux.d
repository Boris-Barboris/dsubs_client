module dsubs_client.core.clipboard.clipboard_linux;

version(linux) {
	import std.process;
	import std.algorithm;
	import std.array;
	import std.utf;

	/**
		Read a string from the clipboard.
	*/
	public wstring readClipboard() {
		auto clip = pipeProcess(["xclip", "-out", "-selection", "clipboard"], Redirect.stdout);
		return toUTF16(cast(string) clip.stdout.byChunk(4096).joiner().array);
	}

	/**
		Write a string to the clipboard.
	*/
	public void writeClipboard(wstring text) {
		auto clip = pipeProcess(["xclip", "-in", "-selection", "clipboard"], Redirect.stdin);
		clip.stdin.write(text);
		clip.stdin.flush();
		clip.stdin.close();
	}

	/**
		Clears the clipboard.
	*/
	public void clearClipboard() {
		writeClipboard(""w);
	}

	/**
		Prepare the console in order to read and write UTF8 strings.
	*/
	public void prepareConsole() {
	}
}