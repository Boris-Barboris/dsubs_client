/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

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
module dsubs_client.gui.stack;

import std.experimental.logger;
import std.conv: to;
import std.math;
import std.meta;
import std.range: retro;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.element;


/// Immutable container that ontains multiple other elements and renders
/// them on top of each other. Does not support content-sized layout,
/// imposes it's size on it's children forcibly.
class Stack: GuiElement
{
	private
	{
		GuiElement[] m_children;
	}

	/// First child is the "deepest", on the bottom of the UI stack
	this(GuiElement[] kids)
	{
		assert(kids.length > 0);
		super();
		m_children = kids;
		foreach (kid; m_children)
		{
			kid.parent = this;
			kid.parentViewport = &viewport();
		}
	}

	@property GuiElement[] children() { return m_children; }

	alias position = typeof(super).position;

	override @property vec2i position(vec2i rhs)
	{
		vec2i diff = rhs - position;
		super.position = rhs;
		foreach (child; m_children)
			child.position = child.position + diff;
		return position;
	}

	override void updateSize()
	{
		super.updateSize();
		updateChildren();
	}

	override void onHide()
	{
		foreach (child; m_children)
			child.onHide();
		super.onHide();
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		foreach (child; m_children)
			child.draw(wnd, usecsDelta);
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (super.getFromPoint(evt, x, y))
		{
			if (m_children.length == 0)
				return this;
			foreach (kid; m_children.retro)
			{
				auto check = kid.getFromPoint(evt, x, y);
				if (check && !check.mouseTransparent)
					return check;
			}
			return this;
		}
		else
			return null;
	}

	protected void updateChildren()
	{
		foreach (child; m_children)
		{
			child.size = this.size;
			child.position = this.position;
		}
	}
}
