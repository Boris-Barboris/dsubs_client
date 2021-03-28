/**
	The clipboard library.
*/
module dsubs_client.core.clipboard.clipboard;

import std.stdio;

/**
	Read a string from the clipboard.
*/
public wstring readClipboard() {
	version(Windows) {
		import dsubs_client.core.clipboard.clipboard_windows;
		return dsubs_client.core.clipboard.clipboard_windows.readClipboard();
	} else version(OSX) {
		import dsubs_client.core.clipboard.clipboard_darwin;
		return clipboard_darwin.readClipboard();
	} else version(linux) {
		import dsubs_client.core.clipboard.clipboard_linux;
		return dsubs_client.core.clipboard.clipboard_linux.readClipboard();
	} else {
		writeln("This plattform is not supported.");
	}
}

/**
	Write a string to the clipboard.
*/
public void writeClipboard(wstring text) {
	version(Windows) {
		import dsubs_client.core.clipboard.clipboard_windows;
		dsubs_client.core.clipboard.clipboard_windows.writeClipboard(text);
	} else version(OSX) {
		import dsubs_client.core.clipboard.clipboard_darwin;
		return clipboard_darwin.writeClipboard(text);
	} else version(linux) {
		import dsubs_client.core.clipboard.clipboard_linux;
		return dsubs_client.core.clipboard.clipboard_linux.writeClipboard(text);
	} else {
		writeln("This plattform is not supported.");
	}
}

/**
	Clears the clipboard.
*/
public void clearClipboard() {
	version(Windows) {
		import dsubs_client.core.clipboard.clipboard_windows;
		dsubs_client.core.clipboard.clipboard_windows.clearClipboard();
	} else version(OSX) {
		import dsubs_client.core.clipboard.clipboard_darwin;
		return clipboard_darwin.clearClipboard();
	} else version(linux) {
		import dsubs_client.core.clipboard.clipboard_linux;
		return dsubs_client.core.clipboard.clipboard_linux.clearClipboard();
	} else {
		writeln("This plattform is not supported.");
	}
}

/**
	Prepare the console in order to read and write UTF8 strings.
*/
public void prepareConsole() {
	version(Windows) {
		import dsubs_client.core.clipboard.clipboard_windows;
		dsubs_client.core.clipboard.clipboard_windows.prepareConsole();
	} else version(OSX) {
		import dsubs_client.core.clipboard.clipboard_darwin;
		return clipboard_darwin.prepareConsole();
	} else version(linux) {
		import dsubs_client.core.clipboard.clipboard_linux;
		return dsubs_client.core.clipboard.clipboard_linux.prepareConsole();
	} else {
		writeln("This plattform is not supported.");
	}
}