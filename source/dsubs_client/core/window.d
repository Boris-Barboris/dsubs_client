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
module dsubs_client.core.window;

import core.stdc.stdlib: free;

import std.algorithm;
import std.array;
import std.string: toStringz;
import std.conv: to;
import std.experimental.logger: info, trace;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
public import derelict.sfml2.window;

import gfm.math.vector;

import dsubs_common.event;


alias sfEventHandler = void delegate(Window, const sfEvent*);

/// wrapper around sfml window
final class Window
{
	this(dstring windowName = "dsubs"d)
	{
		m_mode = sfVideoMode_getDesktopMode();
		info("DesktopMode: ", m_mode);
		m_mode.width = 800; // to!uint(m_mode.width / 1.4);
		m_mode.height = 600; // to!uint(m_mode.height / 1.4);
		m_ctxSettings.depthBits = 24;
		m_ctxSettings.stencilBits = 8;
		m_ctxSettings.antialiasingLevel = 4;
		m_ctxSettings.majorVersion = 2;
		m_ctxSettings.minorVersion = 0;
		m_ctxSettings.attributeFlags = sfContextDefault;
		m_ctxSettings.sRgbCapable = false;
		info("OpenGL context settings: ", m_ctxSettings);
		info("Creating window...");
		m_wnd = sfRenderWindow_createUnicode(m_mode, windowName.ptr,
											sfDefaultStyle, &m_ctxSettings);
		sfRenderWindow_setVerticalSyncEnabled(m_wnd, true);
		info("OK");
		// register default handlers
		registerHandler(sfEvtResized, &resizedHandler);
		m_view = sfView_create();
		// custom sfml patch enables scissor testing
		sfRenderWindow_setScissorTest(m_wnd, true);
		resetView();
	}

	@property void title(string rhs)
	{
		// randomly deadlocks on Windows
		version(linux)
		{
			sfRenderWindow_setTitle(m_wnd, rhs.toStringz);
		}
	}

	// TODO: descructor

	private static const(sfVideoMode)[] getSupportedModes()
	{
		size_t mode_count = 0;
		auto modes = sfVideoMode_getFullscreenModes(&mode_count);
		return modes[0 .. mode_count];
	}

	private static sfVideoMode chooseBiggestMode()
	{
		auto modes = getSupportedModes();
		foreach (m; modes)
			info("Video mode detected: ", m);
		sfVideoMode res = modes[$-1];
		info("Selecting ", res);
		// free(cast(void*)modes.ptr);		// this may crash
		return res;
	}

	void registerHandler(sfEventType type, sfEventHandler handler)
	{
		m_eventHandlers[type] += handler;
	}

	void unregisterHandler(sfEventType type, sfEventHandler handler)
	{
		m_eventHandlers[type] -= handler;
	}

	private bool m_stopFlag = false;

	/// Call this in order to request pollEvents loop exit
	void stopEventProcessing()
	{
		m_stopFlag = true;
	}

	/// Function repeatedly polls events in window buffer and calls
	/// respective handlers, if registered. Blocks until the window is closed, or
	/// waitEvent returns error.
	void pollEvents(scope Object.Monitor mutex)
	{
		sfEvent event;
		while (!m_stopFlag && sfRenderWindow_waitEvent(m_wnd, &event))
		{
			synchronized(mutex)
			{
				m_eventHandlers[event.type](this, &event);
				if (event.type == sfEvtClosed)
				{
					// actually close the window
					info("Standard window close event caught");
					m_stopFlag = true;
				}
			}
		}
	}

	/// Call this after exiting possEvents loop in order to destroy window handle
	void close()
	{
		info("closing window...");
		sfRenderWindow_close(m_wnd);
		m_wnd = null;
		info("OK");
	}

	/// Raw SFML window pointer
	@property sfRenderWindow* wnd() { return m_wnd; }

	@property sfView* view() { return m_view; }

	/// client area width
	@property uint width() const { return m_mode.width; }

	/// client area height
	@property uint height() const { return m_mode.height; }

	/// width-height integer vector
	@property vec2i size() const { return vec2i(m_mode.width.to!int, m_mode.height.to!int); }

	@property vec2i mousePos() const
	{
		return cast(vec2i) sfMouse_getPositionRenderWindow(m_wnd);
	}

	@property bool hasFocus() const { return sfRenderWindow_hasFocus(m_wnd) == sfTrue; }

	// reset view and scissors to window size
	void resetView()
	{
		sfView_reset(m_view, sfFloatRect(0.0f, 0.0f, m_mode.width, m_mode.height));
		sfRenderWindow_setScissor(m_wnd, sfIntRect(0, 0, m_mode.width, m_mode.height));
		sfRenderWindow_setView(m_wnd, m_view);
	}

private:
	sfRenderWindow* m_wnd;
	sfView* m_view;
	sfVideoMode m_mode;
	sfContextSettings m_ctxSettings;
	Event!(void delegate(Window wnd, const sfEvent* evt))[sfEvtCount] m_eventHandlers;

	void resizedHandler(Window wnd, const sfEvent* evt)
	{
		m_mode.width = evt.size.width;
		m_mode.height = evt.size.height;
		// trace("Resize event caught, w=", width, " h=", height);
	}
}
