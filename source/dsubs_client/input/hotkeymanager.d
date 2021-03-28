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
module dsubs_client.input.hotkeymanager;

import std.exception;
import std.algorithm;

public import derelict.sfml2.window;

import dsubs_common.containers.array;

import dsubs_client.core.window;
import dsubs_client.input.router;


/// keyboard modifier
enum Modifier: int
{
	NONE = 0,
	SHIFT = 1 << 0,
	CTRL = 1 << 1,
	ALT = 1 << 2
}

/// builds modifier bitmask from key event
Modifier modFromKey(const(sfKeyEvent)* evt)
{
	Modifier res;
	if (evt.shift)
		res |= Modifier.SHIFT;
	if (evt.alt)
		res |= Modifier.ALT;
	if (evt.control)
		res |= Modifier.CTRL;
	return res;
}

/// hotkey consisting of a key and modifiers
struct Hotkey
{
	sfKeyCode key;
	Modifier mod;
}

/// What to do when key was released
private struct HotkeyAction
{
	void delegate() onRelease;
}

/// What to do if key is being held
alias HoldAction = void delegate(long usecs, Modifier curMods);

/// Class that stores and manages hotkey mapping. Deals with two kinds of
/// inputs: key releases and raw keyboard access.
final class HotkeyManager: IWindowEventSubrouter, IInputReceiver
{
	private
	{
		Window m_wnd;
		HotkeyAction[Hotkey] m_hotkeys;
		bool[sfKeyCount] m_pressed;
		HoldAction[] m_holdkeys;
	}

	this(Window wnd)
	{
		assert(wnd);
		m_wnd = wnd;
	}

	void clear()
	{
		m_hotkeys.clear();
		m_holdkeys.length = 0;
	}

	bool clearHotkey(Hotkey hk)
	{
		return m_hotkeys.remove(hk);
	}

	void clearHoldkeys()
	{
		m_holdkeys.length = 0;
	}

	/// return true if hotkey was overwritten, false otherwise, throws
	/// if the hotkey is invalid.
	bool setHotkey(Hotkey hk, void delegate() onRelease)
	{
		assert(onRelease !is null);
		// TODO: check hotkey
		HotkeyAction* existing = hk in m_hotkeys;
		if (existing !is null)
		{
			*existing = HotkeyAction(onRelease);
			return true;
		}
		m_hotkeys[hk] = HotkeyAction(onRelease);
		return false;
	}

	void addHoldkey(HoldAction action)
	{
		assert(action !is null);
		m_holdkeys ~= action;
	}

	// IWindowEventSubrouter implementation

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		if (evt.type == sfEvtKeyReleased || evt.type == sfEvtKeyPressed)
			return RouteResult(this);
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt) {}

	// IInputReceiver implementation

	void handleKbFocusGain() {}

	void handleKbFocusLoss() {}

	HandleResult handleKeyboard(Window wnd, const sfEvent* evt)
	{
		// this check is required for some undefined keycodes, like printScr wich
		// are out of m_pressed array bounds
		if (evt.key.code >= m_pressed.length)
			return HandleResult(false);
		if (evt.type == sfEvtKeyPressed)
			m_pressed[evt.key.code] = true;
		if (evt.type == sfEvtKeyReleased)
		{
			if (m_pressed[evt.key.code])
			{
				m_pressed[evt.key.code] = false;
				Hotkey hk = Hotkey(evt.key.code, modFromKey(&evt.key));
				HotkeyAction* existing = hk in m_hotkeys;
				if (existing !is null)
					existing.onRelease();
			}
		}
		return HandleResult(false);
	}

	/// interate over all registered HoldKeys and fire their handlers
	void processHeldKeys(long usecs)
	{
		// we don't handle held keys when window does not have focus or when
		// there is a keyboard-capturing component
		if (!m_wnd.hasFocus || InputRouter.kbFocused)
			return;
		Modifier curMod = getCurMod();
		foreach (act; m_holdkeys)
			act(usecs, curMod);
	}

	/// Get bitmask of currently active keyboard modifier keys
	static Modifier getCurMod()
	{
		Modifier res;
		if (sfKeyboard_isKeyPressed(sfKeyLShift))
			res |= Modifier.SHIFT;
		if (sfKeyboard_isKeyPressed(sfKeyRShift))
			res |= Modifier.SHIFT;
		if (sfKeyboard_isKeyPressed(sfKeyLAlt))
			res |= Modifier.ALT;
		if (sfKeyboard_isKeyPressed(sfKeyRAlt))
			res |= Modifier.ALT;
		if (sfKeyboard_isKeyPressed(sfKeyLControl))
			res |= Modifier.CTRL;
		if (sfKeyboard_isKeyPressed(sfKeyRControl))
			res |= Modifier.CTRL;
		return res;
	}

	// dummy IInputReceiver interface functions
	void handleMouseEnter(IInputReceiver oldOwner) {}
	void handleMouseLeave(IInputReceiver newOwner) {}
	void handleMouseFocusGain() {}
	void handleMouseFocusLoss() {}

	HandleResult handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, float delta)
	{
		return HandleResult(true);
	}
}