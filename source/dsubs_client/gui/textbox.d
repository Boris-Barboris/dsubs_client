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
module dsubs_client.gui.textbox;

import std.algorithm.comparison: min, max;
import std.array: replace;
import std.conv: to;
import std.experimental.logger;
import std.string;
import std.math;
import std.utf;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.lib.sfml;
import dsubs_client.lib.fonts;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.element;


/// Multiline readonly text field for big text displaying.
final class TextBox: GuiElement
{
	private
	{
		dstring m_content;
		int m_fontSize = 14;
		string m_fontName = "UbuntuMono";
		int m_padding = 3;
		sfText*[] m_sfTexts;
		sfColor m_fontColor = sfWhite;
	}

	this()
	{
		layoutType = LayoutType.CONTENT;
		mouseTransparent = false;
		m_content = ""d;
	}

	~this()
	{
		foreach (t; m_sfTexts)
			sfText_destroy(t);
	}

	@property dstring content() const { return m_content; }

	// don't call it too often, it's heavy
	@property dstring content(dstring rhs)
	{
		// let's not deal with tabs and replace them by 4 spaces
		m_content = rhs.replace("\t"d, "    "d);
		updateText();
		if (layoutType == LayoutType.CONTENT)
		{
			size = vec2i(size.x, m_textFullHeight);
			if (parent)
				parent.childChanged(this);
		}
		return m_content;
	}

	override void updateSize()
	{
		super.updateSize();
		updateText();
	}

	@property dstring content(string val)
	{
		return content = toUTF32(val);
	}

	invariant
	{
		assert(m_fontSize > 0);
	}

	mixin GetSet!(int, "fontSize",
		"updateFontSize(); updateText();");

	mixin GetSet!(string, "fontName",
		"updateFontname(); updateText();");

	mixin GetSet!(sfColor, "fontColor", "updateFontColor();");

	mixin GetSet!(int, "padding", "updateText();");

	override int doFitContent(Axis fixedDim, Axis contentDim)
	{
		//assert(fixedDim == Axis.X, "Horizontal ContentSize layout is not implemented");
		updateText();
		if (fixedDim == Axis.Y)
			return size.x;
		return m_textFullHeight;
	}

	private int m_textFullHeight = 0;

	// Function that splits content string into lines and packs each one to text sfml object.
	// Lines are wrapped per character.
	private void updateText()
	{
		bool naiiveWidth = true;	// glyph width is estimated naively
		float glyphWidth = getGlyphWidth();

		// we can't fit our text in the textbox this small
		if (glyphWidth > size.x - 2 * m_padding)
		{
			m_textFullHeight = 0;
			return;
		}

		int lineSpacing = getLineSpacing();
		assert(lineSpacing > 0);
		float lineWidth = size.x - 2.0f * m_padding;
		// initial estimate of the number of characters that fit into
		// one line.
		int charsInLine = max(1, floor(lineWidth / glyphWidth).to!int);
		dchar[1024] tmp = 0;	// stack-allocated array to hold the line that is being built
		size_t tmpIdx = 0;		// cursor to fill tmp
		size_t contentIdx = 0;	// cursor to query m_content
		size_t curLineStart = 0;	// cursor in m_content where current line has started
		int lineIdx = 0;		// current line index
		size_t txtIdx = 0;		// cursor of the m_sfTexts element being filled
		size_t wordStartIdx = 0;	// index in m_content of the last work start
		size_t curLineWordStart = 0;	// saved wordStartIdx state at the end of last line

		// write out the word to tmp buffer
		void finalizeWord(bool writeContentIdx, bool reduceTmpIdx = false)
		{
			assert(contentIdx >= 0);
			size_t sepOffset = writeContentIdx ? 0 : 1;
			size_t tmpIdxOffset = reduceTmpIdx ? 0 : 1;
			for (size_t i = wordStartIdx; i < contentIdx - sepOffset; i++)
			{
				size_t tmpWordIdx = tmpIdx + tmpIdxOffset - (contentIdx - i);
				tmp[tmpWordIdx] = m_content[i];
			}
			wordStartIdx = contentIdx;
		}

		bool finalizeLine()
		{
			assert(wordStartIdx <= contentIdx);
			if (wordStartIdx < contentIdx)
			{
				// word is being processed, this is not a new line character
				if (tmpIdx <= (contentIdx - wordStartIdx))
				{
					// Current word is too wide and will never fit using word wrap.
					// We need to use character wrap.
					finalizeWord(true, true);
				}
				else
				{
					// move tmpIdx back to word start
					tmpIdx -= (contentIdx - wordStartIdx);
				}
			}
			if (tmpIdx > 0)
			{
				if (m_sfTexts.length == txtIdx)
					createTextObj();
				sfText* t = m_sfTexts[txtIdx];
				tmp[tmpIdx] = 0;	// zero terminator as if it was a C string
				sfText_setUnicodeString(t, &tmp[0]);
				if (naiiveWidth && tmpIdx > 2)
				{
					// we now get accurate glyph width
					sfFloatRect bounds = sfText_getLocalBounds(t);
					glyphWidth = bounds.width / tmpIdx.to!float;
					if (glyphWidth > 0.0f)
					{
						charsInLine = max(1, floor(lineWidth / glyphWidth).to!int);
						naiiveWidth = false;
						// essentially restart this line building
						contentIdx = curLineStart;
						wordStartIdx = curLineWordStart;
						tmpIdx = 0;
						return false;
					}
				}
				txtIdx++;
				setupTextObj(t, lineIdx, lineSpacing);
			}
			lineIdx++;
			curLineWordStart = wordStartIdx;
			tmpIdx = contentIdx - wordStartIdx;
			curLineStart = contentIdx;
			return true;
		}

	fillerLoop:
		while (contentIdx < m_content.length)
		{
			dchar symb = m_content[contentIdx];
			contentIdx++;
			if (isWordSeparator(symb))
				finalizeWord(symb == cast(dchar)' ');
			if (symb == cast(dchar)'\n')
			{
				finalizeLine();
				continue;
			}
			else
			{
				tmpIdx++;
				if (tmpIdx == charsInLine)
					finalizeLine();
			}
		}
		finalizeWord(true, true);
		if (!finalizeLine())
			goto fillerLoop;	// fuck off

		// we need to detroy unused sfText's:
		for (size_t i = txtIdx; i < m_sfTexts.length; i++)
			sfText_destroy(m_sfTexts[i]);
		m_sfTexts.length = txtIdx;

		m_textFullHeight = (lineIdx + 1) * lineSpacing + m_padding;
	}

	private pragma(inline) bool isWordSeparator(dchar symbol)
	{
		return symbol == cast(dchar)' ' ||
			symbol == cast(dchar)'\n';
	}

	private void createTextObj()
	{
		sfText* t = sfText_create();
		sfText_setFont(t, g_loadedFonts[m_fontName].ptr);
		sfText_setCharacterSize(t, m_fontSize);
		sfText_setColor(t, m_fontColor);
		m_sfTexts ~= t;
	}

	private void setupTextObj(sfText* t, int lineNumber, int interline)
	{
		sfFloatRect bounds = sfText_getLocalBounds(t);
		float x = -bounds.left + m_padding;
		//float x = m_padding;
		int y = interline * lineNumber + m_padding;
		sfText_setPosition(t, sfVector2f(lrint(x), y));
	}

	private float getGlyphWidth() const
	{
		// glyph of 'A'
		sfGlyph g = sfFont_getGlyph(g_loadedFonts[m_fontName].ptr, 65, m_fontSize,
			false, 0.0f);
		return g.bounds.width;
	}

	private int getLineSpacing() const
	{
		return sfFont_getLineSpacing(g_loadedFonts[m_fontName].ptr, m_fontSize).lrint.to!int;
	}

	private void updateFontSize()
	{
		foreach (t; m_sfTexts)
			sfText_setCharacterSize(t, m_fontSize);
	}

	private void updateFontname()
	{
		foreach (t; m_sfTexts)
			sfText_setFont(t, g_loadedFonts[m_fontName].ptr);
	}

	private void updateFontColor()
	{
		foreach (t; m_sfTexts)
			sfText_setColor(t, m_fontColor);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		// drawn m_sfTexts line by line
		// TODO: optimize using viewport, not all lines need to be drawn
		foreach (t; m_sfTexts)
			sfRenderWindow_drawText(wnd.wnd, t, &m_sfRst);
	}
}