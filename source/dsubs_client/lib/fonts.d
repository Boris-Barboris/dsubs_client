/*
DSubs
Copyright (C) 2017-2021 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_client.lib.fonts;

import std.string;
import std.container.rbtree;

import derelict.sfml2.graphics;

import gfm.math.vector: vec4i, vec2f;

import dsubs_client.lib.sfml;


struct FontGlyphParams
{
	int fontSize;	/// font size this params are measured for
	/// if text is placed on x1 and first text pixel is on x2, this is x2 - x1
	int leftOffset;
	/// if text is placed on y1 and first text pixel is on y2, this is y2 - y1
	int topOffset;
	/// actual height of test string
	int actualHeight;
}

/// Font object and it's metadata
struct FontRecord
{
	sfFont* ptr;

	// cache for different font sizes
	private alias RbType = RedBlackTree!(FontGlyphParams, "a.fontSize < b.fontSize");
	private RbType m_glyphParams = new RbType();

	FontGlyphParams glyphParams(int fontSize)
	{
		assert(fontSize > 0);
		auto existingRec = m_glyphParams.equalRange(FontGlyphParams(fontSize));
		if (existingRec.empty)
		{
			auto newRec = runTrial(fontSize);
			m_glyphParams.insert(newRec);
			return newRec;
		}
		return existingRec.front();
	}

	private FontGlyphParams runTrial(int fontSize)
	{
		static dstring g_testStr = "AIjgyl\0"d;
		sfText* text = sfText_create();
		scope(exit) sfText_destroy(text);
		sfText_setFont(text, ptr);
		sfText_setCharacterSize(text, fontSize);
		sfText_setUnicodeString(text, g_testStr.ptr);
		vec4i bounds = sfText_getLocalBounds(text).round;
		return FontGlyphParams(fontSize, bounds[0], bounds[1], bounds[3]);
	}
}

__gshared FontRecord*[string] g_loadedFonts;

immutable string[string] g_fontFiles;

shared static this()
{
	g_fontFiles = [
		"Sans": "fonts/LiberationSans-Regular.ttf",
		"SansMono": "fonts/LiberationMono-Regular.ttf",
		"UbuntuMono": "fonts/ubuntu.mono.ttf",
		"STIX2Math": "fonts/STIX2Math.otf"
	];
}

void loadGlobalFonts()
{
	foreach (string name, string filename; g_fontFiles)
	{
		g_loadedFonts[name] =
			new FontRecord(sfFont_createFromFile(toStringz(filename)));
	}
}
