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
module dsubs_client.gui.textfield;

import std.algorithm.comparison;
import std.conv;
import std.experimental.logger;
import std.math;
import std.utf;
import std.string;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.colorscheme;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.label;
import dsubs_client.core.clipboard.clipboard;


/// One-line editable text field.
class TextField: Label
{
	private
	{
		sfColor m_cursorColor = COLORS.init.textFieldCursor;
		sfRectangleShape* m_cursorRect;
		int m_cursorStart = 0;	// start of selection
		int m_cursorEnd = 0;	// first character after the selection
	}

	this()
	{
		backgroundVisible = true;
		backgroundColor = COLORS.textFieldBgnd;
		m_cursorRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_cursorRect, 0.0f);
		cursorColor = COLORS.textFieldCursor;
		htextAlign = HTextAlign.LEFT;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseMove += &handleMouseMove;
		onKeyPressed += &handeKeyPressed;
		onTextEntered += &handleTextEntered;
		onMouseScroll += &handleMouseScroll;
	}

	~this()
	{
		sfRectangleShape_destroy(m_cursorRect);
	}

	mixin FinalGetSet!(sfColor, "cursorColor",
		"sfRectangleShape_setFillColor(m_cursorRect, rhs);");

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		// first we capture mouse in order to handle text selection
		requestMouseFocus();
		// x and y to local space
		x -= position.x;
		y -= position.y;
		// set m_cursorStart
		m_cursorStart = getCursorFromLocalCoords(x, y);
		m_cursorEnd = m_cursorStart;
		updateCursorVisuals();
	}

	/// move cursor right behind the last character
	void moveCursorToEnd()
	{
		m_cursorEnd = m_cursorStart = max(0, content.length.to!int - 1);
		updateCursorVisuals();
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		returnMouseFocus();
		requestKbFocus();
	}

	private void handleMouseMove(int x, int y)
	{
		if (mouseFocused)
		{
			// x and y to local space
			x -= position.x;
			y -= position.y;
			// set m_cursorStart
			int oldCursorEnd = m_cursorEnd;
			m_cursorEnd = getCursorFromLocalCoords(x, y);
			if (oldCursorEnd != m_cursorEnd)
				updateCursorVisuals();
		}
	}

	private int getCursorFromLocalCoords(int x, int y)
	{
		if (content.length <= 1)
			return 0;
		float charWidth = m_contentWidth / (m_content.length - 1);
		return max(
			0,
			min(
				m_content.length - 1,
				lrint((x - m_contentPos.x) / charWidth)
			)).to!int;
	}

	override void handleKbFocusLoss()
	{
		super.handleKbFocusLoss();
		m_cursorStart = m_cursorEnd = 0;
	}

	void selectAll()
	{
		m_cursorStart = 0;
		m_cursorEnd = m_content.length.to!int - 1;
		updateCursorVisuals();
	}

	protected override void updateText()
	{
		super.updateText();
		// safety check for cursors
		if (content.length <= m_cursorStart)
			m_cursorStart = max(0, m_content.length - 1).to!int;
		if (content.length <= m_cursorEnd)
			m_cursorEnd = max(0, m_content.length - 1).to!int;
		updateCursorVisuals();
	}

	private bool m_updateRecurs = false;

	enum float CARET_H = 1.2f;

	private void updateCursorVisuals()
	{
		float charWidth;
		if (m_content.length <= 1)
		{
			charWidth = 0.0f;
			m_leftOffset = 0;
		}
		else
			charWidth = m_contentWidth / (m_content.length - 1);
		// position of m_cursorStart
		float x_start = m_contentPos.x + charWidth * m_cursorStart + 1.0f;
		// position of m_cursorEnd
		float x_end = x_start + charWidth * (m_cursorEnd - m_cursorStart) + 1.0f;
		if (m_content.length > 1 && !m_updateRecurs)
		{
			// make sure m_cursorEnd is always visible and is located inside
			// element's rectangle
			bool reupdateVisuals = false;
			if (x_end < padding)
			{
				// we need to move text right
				m_leftOffset = min(0, lrint(m_leftOffset - x_end + padding + 1.0f).to!int);
				reupdateVisuals = true;
			}
			else if (x_end > size.x - padding)
			{
				// we need to move text left
				m_leftOffset -= lrint(x_end - size.x + 1.0f + padding).to!int;
				reupdateVisuals = true;
			}
			if (reupdateVisuals)
			{
				// we need to shift the text, let's use recursion
				super.updateText();
				m_updateRecurs = true;
				scope(exit) m_updateRecurs = false;
				updateCursorVisuals();
				return;
			}
		}
		// m_cursorRect width
		float cursorWidth = 2.0f;
		if (m_cursorEnd != m_cursorStart)
			cursorWidth = x_end - x_start;
		float yShift = 0.5f * (CARET_H - 1.0f) * m_contentHeight;
		sfRectangleShape_setPosition(m_cursorRect,
			sfVector2f(x_start, m_contentPos.y - yShift));
		sfRectangleShape_setSize(m_cursorRect,
			sfVector2f(cursorWidth, m_contentHeight * CARET_H));
		m_blinkState = true;
	}

	private static bool m_blinkState = true;
	private static uint m_blinkCounter = 0;
	__gshared uint BLINK_FREQ = 30;

	override void draw(Window wnd, long usecsDelta)
	{
		this.GuiElement.draw(wnd, usecsDelta);	// transform and background rect
		if (kbFocused || mouseFocused)
		{
			// need to draw cursor\selection
			if (m_cursorStart == m_cursorEnd)
			{
				// we have no text selected, display blinking caret
				m_blinkCounter++;	// framerate-dependent, but i don't really care
				if (m_blinkCounter % BLINK_FREQ == 0)
					m_blinkState = !m_blinkState;
				if (m_blinkState)
					sfRenderWindow_drawRectangleShape(wnd.wnd, m_cursorRect, &m_sfRst);
			}
			else
				sfRenderWindow_drawRectangleShape(wnd.wnd, m_cursorRect, &m_sfRst);
		}
		// text is drawn over the cursor rectangle
		sfRenderWindow_drawText(wnd.wnd, m_sfText, &m_sfRst);
	}

	protected void insertAt(dchar c, size_t idx)
	{
		m_content.insertAt(c, idx);
	}

	protected void insertAt(dstring s, size_t idx)
	{
		m_content.insertAt(s, idx);
	}

	protected void removeAt(size_t idx)
	{
		m_content.removeAt(idx);
	}

	protected void removeInterval(size_t start, size_t end)
	{
		m_content.removeInterval(start, end);
	}

	// function to filter entered symbols by. Should return true if
	// symbol is acceptable, false otherwise.
	bool function(dchar) symbolFilter;

	protected void doHandleText(dchar c)
	{
		// first we check wether we had range of symbols selected
		if (m_cursorStart == m_cursorEnd)
		{
			// it's just a caret
			switch (c)
			{
				case '\b':	// backspace
					if (m_content.length > 1 && m_cursorStart > 0)
					{
						removeAt(m_cursorStart - 1);
						m_cursorStart = m_cursorEnd = m_cursorStart - 1;
					}
					break;
				default:
					//trace("captured unicode symbol ", c.to!uint);
					if (symbolFilter && !symbolFilter(c))
					{
						//trace("ignored by filter");
						return;
					}
					insertAt(c, m_cursorStart);
					m_cursorStart = m_cursorEnd = m_cursorStart + 1;
					break;
			}
		}
		else
		{
			// range is selected
			int orderedStart = min(m_cursorStart, m_cursorEnd);
			int orderedEnd = max(m_cursorStart, m_cursorEnd);
			switch (c)
			{
				case '\b':	// backspace
					removeInterval(orderedStart, orderedEnd - 1);
					m_cursorStart = m_cursorEnd = orderedStart;
					break;
				default:
					//trace("captured unicode symbol ", c.to!uint);
					if (symbolFilter && !symbolFilter(c))
					{
						//trace("ignored by filter");
						return;
					}
					removeInterval(orderedStart, orderedEnd - 1);
					insertAt(c, orderedStart);
					m_cursorStart = m_cursorEnd = orderedStart + 1;
					break;
			}
		}
		// update sfml text
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	protected void doHandleString(dstring s)
	{
		if (s.length == 0)
			return;
		// first we check wether we had range of symbols selected
		if (m_cursorStart == m_cursorEnd)
		{
			insertAt(s, m_cursorStart);
			m_cursorStart = m_cursorEnd = m_cursorStart + s.length.to!int;
		}
		else
		{
			// range is selected
			int orderedStart = min(m_cursorStart, m_cursorEnd);
			int orderedEnd = max(m_cursorStart, m_cursorEnd);
			removeInterval(orderedStart, orderedEnd - 1);
			insertAt(s, orderedStart);
			m_cursorStart = m_cursorEnd = orderedStart + s.length.to!int;
		}
		// update sfml text
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	private void handleMouseScroll(int x, int y, float delta)
	{
		if (kbFocused && !mouseFocused)
		{
			m_cursorStart = max(0, min(m_content.length - 1,
				lrint(m_cursorStart + delta).to!int));
			m_cursorEnd = m_cursorStart;
			updateCursorVisuals();
		}
	}

	private void handeKeyPressed(const sfKeyEvent* kevt)
	{
		switch (kevt.code)
		{
			case sfKeyLeft:
				if (kevt.shift)
					m_cursorEnd = max(0, m_cursorEnd - 1);
				else
				{
					m_cursorStart = max(0, m_cursorStart - 1);
					m_cursorEnd = m_cursorStart;
				}
				updateCursorVisuals();
				break;
			case sfKeyRight:
				if (kevt.shift)
					m_cursorEnd = min(m_content.length - 1, m_cursorEnd + 1);
				else
				{
					m_cursorStart = min(m_content.length - 1, m_cursorStart + 1);
					m_cursorEnd = m_cursorStart;
				}
				updateCursorVisuals();
				break;
			case sfKeyHome:
				if (kevt.shift)
					m_cursorEnd = 0;
				else
					m_cursorStart = m_cursorEnd = 0;
				updateCursorVisuals();
				break;
			case sfKeyEnd:
				if (kevt.shift)
					m_cursorEnd = m_content.length.to!int - 1;
				else
					m_cursorStart = m_cursorEnd = m_content.length.to!int - 1;
				updateCursorVisuals();
				break;
			case sfKeyA:
				if (kevt.control)
				{
					m_cursorStart = 0;
					m_cursorEnd = m_content.length.to!int - 1;
					updateCursorVisuals();
				}
				break;
			case sfKeyDelete:
				if (m_cursorStart == m_cursorEnd)
				{
					if (m_cursorStart < m_content.length - 1)
						removeAt(m_cursorStart);
				}
				else
				{
					int orderedStart = min(m_cursorStart, m_cursorEnd);
					int orderedEnd = max(m_cursorStart, m_cursorEnd);
					removeInterval(orderedStart, orderedEnd - 1);
					m_cursorStart = m_cursorEnd = orderedStart;
				}
				// update sfml text
				sfText_setUnicodeString(m_sfText, m_content.ptr);
				updateText();
				break;
			case sfKeyV:
				if (kevt.control)
				{
					wstring cont = readClipboard();
					doHandleString(cont.toUTF32);
				}
				break;
			case sfKeyReturn:
				// we interpret enter as desire to commit changes and return
				// keyboard focus
				returnKbFocus();
				break;
			default:
				break;
		}
	}

	private void handleTextEntered(const sfTextEvent* evt)
	{
		dchar c = evt.unicode;
		switch (c)
		{
			case '\r':
				break;
			case '\n':
				break;
			case '\t':
				break;
			case 27:
				// ESC button
				returnKbFocus();
				break;
			case 127:
				// Delete button
				break;
			default:
				if (c >= 32 || c == '\b')
					doHandleText(c);
		}
	}
}
