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
module dsubs_client.gui.contextmenu;

import std.algorithm;

import derelict.sfml2.window;
import derelict.sfml2.graphics;

import dsubs_client.common;
import dsubs_client.gui.element;
import dsubs_client.gui.div;
import dsubs_client.gui.button;
import dsubs_client.gui.label;
import dsubs_client.gui.manager;
import dsubs_client.input.router: IInputReceiver;


/// Context menu, tipically invoked by right click. Can be nested.
/// Is responsible for it's own visibility on the window.
final class ContextMenu: Panel
{
	@property Div rootDiv() { return cast(Div) root; }

	this(Button[] elements, int rowHeight)
	{
		Div div = vDiv(cast(GuiElement[]) elements);
		div.fixedSize = vec2i(100, (rowHeight * elements.length).to!int);
		// now adapt div width to max content size of buttons
		float maxContentWidth = elements.map!(
			e => (e.contentWidth + 2 * e.padding)).reduce!(max);
		div.fixedSize = vec2i(lrint(maxContentWidth).to!int, div.size.y);
		div.backgroundColor = COLORS.simButtonBgnd;
		// apply shanges to buttons
		foreach (Button btn; elements)
		{
			btn.htextAlign = HTextAlign.LEFT;
			NestedContextBtn ncb = cast(NestedContextBtn) btn;
			if (ncb !is null)
				ncb.m_parentMenu = this;
			else
				btn.onClick += &teardownFromTopParent;
		}
		super(div);
	}

	private ContextMenu m_childMenu;
	private ContextMenu m_parentMenu;

	private void teardownFromTopParent()
	{
		if (m_parentMenu)
			m_parentMenu.teardownFromTopParent();
		else
			teardownWithChildren();
	}

	private void teardownWithChildren()
	{
		if (m_parentMenu)
		{
			m_parentMenu.m_childMenu = null;
			m_parentMenu = null;
		}
		if (m_childMenu)
		{
			m_childMenu.teardownWithChildren();
			m_childMenu = null;
		}
		if (manager)
			manager.removePanel(this);
	}

	/// Place the root div in such a way that it's left upper corner
	/// is preferably at 'luCorner', but can be moved in order to fit in windowSize.
	void placeByLUCorner(vec2i windowSize, vec2i luCorner)
	{
		vec2i pos = vec2i(
			min(windowSize.x - rootDiv.size.x, luCorner.x),
			min(windowSize.y - rootDiv.size.y, luCorner.y));
		rootDiv.position = pos;
	}

	/// Called by top-level menu. Returns true if for some reason top-level
	/// menu should not immediately destroy itself, but should wait
	private bool leftClickAllowed(const sfEvent* evt, int x, int y)
	{
		if (m_childMenu && m_childMenu.leftClickAllowed(evt, x, y))
			return true;
		GuiElement el = rootDiv.getFromPoint(evt, x, y);
		return (el !is null);
	}

	/// Add this context menu to GuiManager and aquire mouse focus
	void activate(GuiManager mgr)
	{
		foreach (GuiElement btn; rootDiv.children)
		{
			NestedContextBtn ncb = cast(NestedContextBtn) btn;
			if (ncb)
				ncb.m_mgr = mgr;
		}
		// handle focus loss
		rootDiv.onMouseFocusLoss += &teardownWithChildren;

		rootDiv.onMouseDown += (int x, int y, sfMouseButton btn) {
			// handle a click outside of the context menu
			if (btn == sfMouseLeft)
			{
				sfEvent evt;
				evt.mouseButton = sfMouseButtonEvent(sfEvtMouseButtonPressed,
					sfMouseLeft, x, y);
				if (leftClickAllowed(&evt, x, y))
					return;
			}
			rootDiv.returnMouseFocus();
		};
		mgr.addPanel(this);
		rootDiv.requestMouseFocus();
	}

	void activateChained(GuiManager mgr, ContextMenu parentMenu)
	{
		m_parentMenu = parentMenu;
		parentMenu.m_childMenu = this;
		mgr.addPanel(this);
	}

	/// returns true if need to remove panel
	private bool checkNewOwnerForChained(IInputReceiver newOwner)
	{
		if (newOwner is null)
			return true;
		if (rootDiv is newOwner)
			return false;
		if (divOwnsInputReceiver(rootDiv, newOwner))
			return false;
		if (m_childMenu)
			return m_childMenu.checkNewOwnerForChained(newOwner);
		return true;
	}
}

bool divOwnsInputReceiver(Div d, IInputReceiver r)
{
	GuiElement el = cast(GuiElement) r;
	return (el && el.parent is d);
}


/// Button that on hover spawns the inner context menu
class NestedContextBtn: Button
{
	this(Button[] elements, int rowHeight = 20)
	{
		m_toSpawn = elements;
		m_rowHeight = rowHeight;
		onMouseEnter += &processMouseEnter;
		onMouseLeave += &processMouseLeave;
	}

	private void processMouseEnter(IInputReceiver oldOwner)
	{
		if (m_spawnedMenu)
			m_spawnedMenu.teardownWithChildren();
		if (m_parentMenu.m_childMenu)
			m_parentMenu.m_childMenu.teardownWithChildren();
		m_spawnedMenu = new ContextMenu(m_toSpawn, m_rowHeight);
		vec2i unclamped = position + vec2i(size.x, 0);
		m_spawnedMenu.placeByLUCorner(m_mgr.window.size, unclamped);
		if (m_spawnedMenu.rootDiv.position.x < unclamped.x)
			m_spawnedMenu.placeByLUCorner(m_mgr.window.size,
				position - vec2i(m_spawnedMenu.rootDiv.size.x, 0));
		m_spawnedMenu.activateChained(m_mgr, m_parentMenu);
	}

	private void processMouseLeave(IInputReceiver newOwner)
	{
		if (!m_spawnedMenu || !m_spawnedMenu.checkNewOwnerForChained(newOwner))
			return;
		m_spawnedMenu.teardownWithChildren();
		m_spawnedMenu = null;
	}

	private
	{
		GuiManager m_mgr;
		ContextMenu m_parentMenu;
		ContextMenu m_spawnedMenu;
		Button[] m_toSpawn;
		int m_rowHeight;
	}
}


/// Build, place and activate the context menu on a gui manager
ContextMenu contextMenu(GuiManager mgr, Button[] elements,
	vec2i wndSize, vec2i luCorner, int rowHeight = 20)
{
	ContextMenu menu = new ContextMenu(elements, rowHeight);
	menu.placeByLUCorner(wndSize, luCorner);
	menu.activate(mgr);
	return menu;
}