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
module dsubs_client.gui.button;

import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_common.event;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.label;
import dsubs_client.input.router: IInputReceiver;


enum ButtonType: ubyte
{
	SYNC,		/// onclick event is synchronous, instant return to unpressed state
	ASYNC,		/// onclick event is asynchronous, button must be unpressed from the outside
	TOGGLE		/// synchronous toggle
}

/// State wich is relevant for ASYNC and TOGGLE buttons.
enum ButtonState: bool
{
	INACTIVE = false,
	ACTIVE = true,		/// toggle is active, or asynchronous operation is running
}

class Button: Label
{
	private
	{
		ButtonType m_buttonType;
		sfColor m_textPressedColor = sfColor(255, 25, 25, 255);
		sfColor m_hoverColor = sfColor(255, 150, 150, 255);
		alias m_textReleasedColor = m_fontColor;

		/// true when user has pressed the button down, but didn't release it
		bool m_pressed;
		bool m_pressable = true;
		ButtonState m_state;	/// actual internal state of the button in toggle\async mode
	}

	this(ButtonType type = ButtonType.SYNC)
	{
		htextAlign = HTextAlign.CENTER;
		m_buttonType = type;
		updateFontColor();
		onMouseEnter += &handleMouseEnter;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseLeave += &handleMouseLeave;
	}

	final @property ButtonType buttonType() const { return m_buttonType; }

	mixin FinalGetSet!(sfColor, "textPressedColor", "updateFontColor();");
	mixin FinalGetSet!(sfColor, "textReleasedColor", "updateFontColor();");

	/// Intermidiate color between pressed and unpressed, used for hover
	mixin FinalGetSet!(sfColor, "hoverColor", "updateFontColor();");

	// whether user is currently holding the button down
	final @property bool pressed() const { return m_pressed; }

	private @property bool pressed(bool rhs)
	{
		m_pressed = rhs;
		updateFontColor();
		return m_pressed;
	}

	final @property bool pressable() const { return m_pressable; }
	final @property void pressable(bool rhs)
	{
		if (m_pressable != rhs)
		{
			m_pressable = rhs;
			if (!rhs)
				m_pressed = false;
			updateFontColor();
		}
	}

	// internal state, bool. Is true when toggle is activated or
	// async button is in the process of handling a click.
	final @property ButtonState state() const { return m_state; }

	// force set the internal bool state, used for toggle buttons
	@property void state(ButtonState rhs)
	{
		assert(m_buttonType == ButtonType.TOGGLE);
		if (m_state != rhs)
		{
			m_state = rhs;
			updateFontColor();
		}
	}

	private void updateFontColor()
	{
		if (!m_pressed && m_underCursor && m_pressable)
		{
			sfText_setColor(m_sfText, m_hoverColor);
			return;
		}
		if (m_state != m_pressed)
			sfText_setColor(m_sfText, m_textPressedColor);
		else
			sfText_setColor(m_sfText, m_textReleasedColor);
	}

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft || !m_pressable)
			return;
		pressed = true;
	}

	private bool m_underCursor = false;

	private void handleMouseLeave(IInputReceiver newOwner)
	{
		m_underCursor = false;
		pressed = false;
	}

	private void handleMouseEnter(IInputReceiver oldOwner)
	{
		m_underCursor = true;
		updateFontColor();
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		if (m_pressed)
		{
			simulateClick();
			pressed = false;
		}
	}

	final void simulateClick()
	{
		pressed = true;
		final switch (m_buttonType)
		{
			case ButtonType.TOGGLE:
				m_state = cast(ButtonState)!m_state;
				onClick();
				break;
			case ButtonType.SYNC:
				onClick();
				break;
			case ButtonType.ASYNC:
				if (m_state == ButtonState.INACTIVE)
				{
					m_state = ButtonState.ACTIVE;
					onClick();
				}
		}
		pressed = false;
	}

	/// Call this for ASYNC button to finish the click
	void signalClickEnd()
	{
		assert(m_buttonType == ButtonType.ASYNC);
		m_state = ButtonState.INACTIVE;
		updateFontColor();
	}

	Event!(void delegate()) onClick;
}
