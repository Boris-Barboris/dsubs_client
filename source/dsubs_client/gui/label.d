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
module dsubs_client.gui.label;

import std.conv;
import std.string;
import std.math;
import std.utf;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_common.mutstring;

import dsubs_client.lib.sfml;
import dsubs_client.lib.fonts;
import dsubs_client.colorscheme;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.element;


enum HTextAlign: ubyte
{
	LEFT = 0,
	CENTER = 1,
	RIGHT = 2,
}

enum VTextAlign: ubyte
{
	TOP = 0,
	CENTER = 1,
	BOTTOM = 2,
}

/// Single-line text container
class Label: GuiElement
{
	private
	{
		int m_fontSize = 14;
		string m_fontName = "UbuntuMono";
		HTextAlign m_htextAlign = HTextAlign.LEFT;
		VTextAlign m_vtextAlign = VTextAlign.CENTER;
		int m_padding = 4;
	}

	protected
	{
		sfText* m_sfText;
		dmutstring m_content;
		sfColor m_fontColor = COLORS.init.defaultFont;
	}

	this()
	{
		mouseTransparent = false;
		m_content = _s(""d, 31);
		initializeText();
	}

	~this()
	{
		sfText_destroy(m_sfText);
	}

	private void initializeText()
	{
		m_sfText = sfText_create();
		sfText_setFont(m_sfText, g_loadedFonts[m_fontName].ptr);
		sfText_setCharacterSize(m_sfText, m_fontSize);
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		m_fontColor = COLORS.defaultFont;
		sfText_setColor(m_sfText, m_fontColor);
	}

	/// null-terminated c-string content
	@property dmutstring content() { return m_content; }

	@property void content(dmutstring rhs)
	{
		m_content = rhs;
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	@property void content(dstring rhs)
	{
		str2mutCopy(rhs, m_content);
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	@property void content(string rhs)
	{
		content = toUTF32(rhs);
	}

	void format(string fmt, Args...)(Args args)
	{
		mutsformat!(fmt, Args)(m_content, args);
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	invariant
	{
		assert(m_fontSize > 0);
	}

	mixin GetSet!(int, "fontSize",
		"sfText_setCharacterSize(m_sfText, rhs); updateText();");

	mixin GetSet!(string, "fontName",
		"sfText_setFont(m_sfText, g_loadedFonts[rhs].ptr); updateText();");

	mixin GetSet!(sfColor, "fontColor",
		"sfText_setColor(m_sfText, rhs);");

	mixin FinalGetSet!(int, "padding", "updateText();");

	mixin FinalGetSet!(HTextAlign, "htextAlign", "updateText();");

	mixin FinalGetSet!(VTextAlign, "vtextAlign", "updateText();");

	protected
	{
		vec2i m_contentPos;	/// Estimated position of text first glyph.
		vec2i m_textPos;	/// Position of text sfml object
		float m_contentWidth = 0.0f;
		float m_contentHeight = 0.0f;
		int m_leftOffset;		// needed for textfield
	}

	final float contentWidth() const { return m_contentWidth; }
	final float contentHeight() const { return m_contentHeight; }

	override void updateSize()
	{
		super.updateSize();
		updateText();
	}

	protected int getLineSpacing() const
	{
		return sfFont_getLineSpacing(g_loadedFonts[m_fontName].ptr, m_fontSize).lrint.to!int;
	}

	// update text position
	protected void updateText()
	{
		FontGlyphParams glyphParams = g_loadedFonts[m_fontName].glyphParams(m_fontSize);
		sfFloatRect bounds = sfText_getLocalBounds(m_sfText);
		float x, y; // resultsing text element position
		final switch (m_htextAlign)
		{
			case HTextAlign.LEFT:
				x = m_padding - glyphParams.leftOffset + m_leftOffset;
				break;
			case HTextAlign.RIGHT:
				x = size.x - m_padding - glyphParams.leftOffset - bounds.width + m_leftOffset;
				break;
			case HTextAlign.CENTER:
				x = 0.5f * (size.x - bounds.width) - glyphParams.leftOffset + m_leftOffset;
		}
		m_textPos.x = lrint(x).to!int;
		m_contentPos.x = m_textPos.x + glyphParams.leftOffset;
		m_contentWidth = bounds.width;
		final switch (m_vtextAlign)
		{
			case VTextAlign.TOP:
				y = m_padding - glyphParams.topOffset;
				break;
			case VTextAlign.BOTTOM:
				y = size.y - m_padding - m_fontSize - glyphParams.topOffset;
				break;
			case VTextAlign.CENTER:
				y = 0.5f * (size.y - m_fontSize) - 0.5f * glyphParams.topOffset;
		}
		m_textPos.y = lrint(y).to!int;
		m_contentPos.y = m_textPos.y + glyphParams.topOffset;
		m_contentHeight = glyphParams.actualHeight;
		sfText_setPosition(m_sfText, m_textPos.tosf);
	}

	override int doFitContent(Axis fixedDim, Axis contentDim)
	{
		if (fixedDim == Axis.X)
			return m_fontSize + 5;
		else
			return (m_contentWidth + 10.0).lrint.to!int;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		sfRenderWindow_drawText(wnd.wnd, m_sfText, &m_sfRst);
	}
}
