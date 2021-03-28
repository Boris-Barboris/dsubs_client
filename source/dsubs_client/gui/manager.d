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
module dsubs_client.gui.manager;

import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.containers.dlist;

import dsubs_client.core.utils;
import dsubs_client.lib.sfml;
import dsubs_client.input.router;
import dsubs_client.render.render: IWindowDrawer;
import dsubs_client.gui.element;


/** Gui router explicitly handles only mouse events.
This structure is returned by GuiElements when trying to
route the mouse event. Interceptor is a tree leaf, that was placed under
the cursor. The leaf may choose to let the event go through, by setting
mouse_transparent to true. */
package struct GuiRouteResult
{
	GuiElement mouseReciever;
	bool mouseTransparent = true;
}

/// Primitive panel, wich consists of one GuiElement tree.
class Panel
{
	private GuiElement m_root;
	final @property GuiElement root() { return m_root; }

	private GuiManager m_manager;
	final @property GuiManager manager() { return m_manager; }

	private DList!(Panel).Iterator m_zorderIter;

	/// returns true when the panel is added to manager
	@property bool added() const { return m_manager !is null; }

	/// If true, mouse click will push this panel on top of the stack.
	bool zboost = false;

	this(GuiElement root)
	{
		assert(root);
		m_root = root;
	}

	void onHide()
	{
		m_root.onHide();
	}

	protected void draw(Window wnd, long usecsDelta) { m_root.draw(wnd, usecsDelta); }

	protected GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		return m_root.routeMousePos(evt, x, y);
	}

	protected void handleWindowResize(const sfSizeEvent* evt)
	{
		// greedy roots are fullscreen by convention
		if (m_root.layoutType == LayoutType.GREEDY)
		{
			m_root.position = vec2i(0, 0);
			m_root.size = vec2i(evt.width, evt.height);
		}
	}
}

/// Container for all gui elements on one window. Draws them
/// and dispatches input. Implements z-ordering.
final class GuiManager: IWindowDrawer, IWindowEventSubrouter
{
	private Window m_wnd;
	@property Window window() { return m_wnd; }

	this(Window wnd)
	{
		m_wnd = wnd;
	}

	void draw(Window wnd, long usecsDelta)
	{
		// deepest panels first
		foreach (panel; panels[])
			panel.draw(wnd, usecsDelta);
	}

	// Z-ordered list of GuiElement trees.
	// First (front) element is the deepest one.
	private DList!Panel panels;

	/// register a panel in a manager and place it on top of all existing panels
	void addPanel(Panel p)
	{
		assert(p.m_manager is null, "panel already belongs to some manager");
		panels.insertBack(p);
		p.m_manager = this;
		p.m_zorderIter = panels.last;
		// initial shakedown in order to befriend new panel
		// with current window size
		sfSizeEvent fake = sfSizeEvent(sfEvtResized, m_wnd.width, m_wnd.height);
		p.handleWindowResize(&fake);
	}

	void removePanel(Panel p)
	{
		assert(p.m_manager is this, "panel does not belong to this manager");
		p.onHide();
		panels.remove(p.m_zorderIter);
		p.m_manager = null;
	}

	void clearPanels()
	{
		foreach (panel; panels[])
		{
			panel.onHide();
			panel.m_manager = null;
		}
		panels.clear();
	}

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		// look for reciever from top to bottom of z-ordered panel stack
		for (auto i = panels.last; !i.end; i.prev)
		{
			Panel panel = i.val;
			res = panel.routeMousePos(evt, x, y);
			if (res.mouseReciever)
			{
				if (res.mouseTransparent)
					continue;
				if (evt.type == sfEvtMouseButtonPressed && panel.zboost)
				{
					// default behaviour of moving clicked panel to
					// the top of z-stack
					panels.remove(i);
					panels.insertBack(panel);
					panel.m_zorderIter = panels.last;
				}
				return RouteResult(res.mouseReciever);
			}
		}
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		// GUI captures keyboard only through focus mechanics
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt)
	{
		// TODO: resize handling for greedy and fraction-sized panels, out-of
		// window border check etc.
		foreach (panel; panels[])
			panel.handleWindowResize(evt);
	}
}
