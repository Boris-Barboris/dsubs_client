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
module dsubs_client.gui.div;

import std.algorithm;
import std.array: insertInPlace;
import std.experimental.logger;
import std.conv: to;
import std.math;
import std.meta;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_common.containers.array;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.element;


enum DivType
{
	HORZ,	/// children left/right of each other
	VERT	/// children above/below each other
}

/// Linear layout manager, rectangular one-dimentional array of elements
class Div: GuiElement
{
	public
	{
		immutable int dim;
		immutable int odim;
		immutable Axis fixedAxis;
	}

	private
	{
		int m_borderWidth = 0;
		/// array of rectangles representing external border
		sfRectangleShape*[4] m_divBorders;
		GuiElement[] m_children;
	}

	protected
	{
		bool m_updatingKids = false;	/// anti-recusrion flag.
		sfColor m_borderColor = sfTransparent;
		/// array of rectangles that are used to draw inter-child borders
		sfRectangleShape*[] m_cellBorders;
	}

	this(DivType divType, GuiElement[] kids)
	{
		assert(kids.length > 0);

		if (divType == DivType.HORZ)
		{
			dim = 0;
			odim = 1;
			fixedAxis = Axis.Y;
		}
		else
		{
			dim = 1;
			odim = 0;
			fixedAxis = Axis.X;
		}

		super();
		m_children = kids;
		foreach (kid; m_children)
		{
			kid.parent = this;
			kid.parentViewport = &viewport();
		}
		// borders between m_children, kids.length - 1 borders to be exact
		foreach (ref brd; m_divBorders)
		{
			brd = sfRectangleShape_create();
			sfRectangleShape_setOutlineThickness(brd, 0);
			sfRectangleShape_setFillColor(brd, m_borderColor);
		}
		m_cellBorders.reserve(m_children.length - 1);
		for (int i = 1; i < m_children.length; i++)
		{
			sfRectangleShape* brd = sfRectangleShape_create();
			sfRectangleShape_setOutlineThickness(brd, 0);
			sfRectangleShape_setFillColor(brd, m_borderColor);
			m_cellBorders ~= brd;
		}
	}

	~this()
	{
		foreach (border; m_cellBorders)
			sfRectangleShape_destroy(border);
		foreach (border; m_divBorders)
			sfRectangleShape_destroy(border);
	}

	@property GuiElement[] children() { return m_children; }

	mixin FinalGetSet!(int, "borderWidth", "updateChildren();");

	mixin FinalGetSet!(sfColor, "borderColor", "updateBorderColor();");

	protected void updateBorderColor()
	{
		foreach (r; m_cellBorders)
			sfRectangleShape_setFillColor(r, m_borderColor);
		foreach (r; m_divBorders)
			sfRectangleShape_setFillColor(r, m_borderColor);
	}

	private void addNewCellBorder()
	{
		sfRectangleShape* brd = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(brd, 0);
		sfRectangleShape_setFillColor(brd, m_borderColor);
		m_cellBorders ~= brd;
	}

	private void removeLastCellBorder()
	{
		if (m_cellBorders.length == 0)
			return;
		sfRectangleShape_destroy(m_cellBorders[$-1]);
		m_cellBorders.length -= 1;
	}

	/// set idx child in children array to newChild and return
	/// the old one.
	GuiElement setChild(GuiElement newChild, size_t idx)
	{
		GuiElement old;
		if (idx < m_children.length)
		{
			old = m_children[idx];
			old.parent = null;
			old.parentViewport = null;
			old.onHide();
		}
		else
			addNewCellBorder();
		newChild.parent = this;
		newChild.parentViewport = &viewport();
		m_children[idx] = newChild;
		onChildrenSetChanged();
		return old;
	}

	/// add new child, it's new index in the children array will be atIdx
	void addChild(GuiElement newChild, size_t atIdx)
	{
		assert(atIdx <= m_children.length);
		addNewCellBorder();
		newChild.parent = this;
		newChild.parentViewport = &viewport();
		m_children.insertInPlace(atIdx, newChild);
		onChildrenSetChanged();
	}

	GuiElement removeChildAt(size_t atIdx)
	{
		assert(atIdx < m_children.length);
		GuiElement old = m_children[atIdx];
		old.parent = null;
		old.parentViewport = null;
		old.onHide();
		m_children = m_children.remove(atIdx);
		removeLastCellBorder();
		onChildrenSetChanged();
		return old;
	}

	bool removeChild(GuiElement child)
	{
		if (child is null)
			return false;
		if (removeFirst(m_children, child))
		{
			child.parent = null;
			child.parentViewport = null;
			child.onHide();
			removeLastCellBorder();
			onChildrenSetChanged();
			return true;
		}
		return false;
	}

	protected void onChildrenSetChanged()
	{
		if (layoutType == LayoutType.CONTENT)
			fitContent(fixedAxis, size[odim]);
		updateChildren();
	}

	override void childChanged(GuiElement child)
	{
		// kids are expected to notify us on their size/layout property changes
		if (!m_updatingKids)
		{
			if (layoutType == LayoutType.CONTENT)
				fitContent(fixedAxis, size[odim]);
			updateChildren();
		}
	}

	private vec2i dimVec(int dimVal, int odimVal) const
	{
		vec2i res;
		res[dim] = dimVal;
		res[odim] = odimVal;
		return res;
	}

	private @property bool extBordersHidden() const
	{
		return (cast(Div) parent || (parent is null && layoutType == LayoutType.GREEDY));
	}

	// we don't display external border if our parent is div
	protected final @property int externalBorder() const
	{
		if (extBordersHidden)
			return 0;
		else
			return m_borderWidth;
	}

	private vec2i dimSizeVec(int dimVal) const
	{
		assert(dimVal >= 0);
		return dimVec(dimVal, max(0, size[odim] - 2 * externalBorder));
	}

	/// Set to true in order to ignore FIXED layout-type elements
	/// in doFitContent while determining required size.
	bool contentLayoutIgnoreFixed = false;

	override int doFitContent(Axis fixedDim, Axis contentDim)
	{
		int requiredSize = 0;
		m_updatingKids = true;
		scope(exit) m_updatingKids = false;

		void function(ref int accumulSize, const int nextElSize)
			accumulate;

		if (fixedDim == odim)
		{
			// example: vdiv that can grow vertically and fixedDim is x.
			requiredSize += m_borderWidth * (m_children.length.to!int - 1) +
				2 * externalBorder;
			// we calculate the summ of elements
			accumulate = (ref int accumulSize, const int nextElSize)
			{
				accumulSize += nextElSize;
			};
		}
		else
		{
			// example: vdiv that can grow vertically and fixedDim is y.
			requiredSize += 2 * externalBorder;
			accumulate = (ref int accumulSize, const int nextElSize)
			{
				accumulSize = max(accumulSize, nextElSize);
			};
		}

		foreach (child; m_children)
		{
			switch (child.layoutType)
			{
				case LayoutType.FIXED:
					if (!contentLayoutIgnoreFixed)
						accumulate(requiredSize, child.size[contentDim]);
					break;
				case LayoutType.CONTENT:
					accumulate(requiredSize, child.fitContent(
						fixedDim, size[fixedDim] - 2 * externalBorder));
					break;
				default:
					break;
			}
		}
		return requiredSize;
	}

	protected int pureChildrenBudget()
	{
		return size[dim] - m_borderWidth * (m_children.length.to!int - 1) -
			2 * externalBorder;
	}

	// recalculate children layout
	protected void updateChildren()
	{
		m_updatingKids = true;
		int intBudget = pureChildrenBudget();
		float budget = max(0, intBudget);
		// fixed-sized kids go first
		int childCount = 0;
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.FIXED))
		{
			float childSize = chip(budget, child.size[dim]);
			budget -= childSize;
			child.size = dimSizeVec(child.size[dim]);
			childCount++;
		}
		// content-sized kids determine their size on their own
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.CONTENT))
		{
			budget -= child.fitContent(fixedAxis, size[odim] - 2 * externalBorder);
			childCount++;
		}
		// now fractual kids
		auto fractKids = m_children.filter!(a => a.layoutType == LayoutType.FRACT);
		float fractSum = fold!((a, b) => a + b.fraction)(fractKids, 0.0f);
		fractSum = fmax(1.0f, fractSum);
		budget = fmax(0.0f, budget);
		float budgetSave = budget;
		foreach (child; fractKids)
		{
			float newSize = child.fraction / fractSum * budgetSave;
			child.size = dimSizeVec(lrint(newSize).to!int);
			budget -= newSize;
			childCount++;
		}
		// and now greedy ones
		int greedyCount = m_children.length.to!int - childCount;
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.GREEDY))
		{
			float newSize = chip(budget, budget / greedyCount);
			child.size = dimSizeVec(lrint(newSize).to!int);
		}
		// all offsets now are calcuated, we can set positions
		int offset = externalBorder;
		foreach (i, child; m_children)
		{
			child.position = position + dimVec(offset, externalBorder);
			offset += child.size[dim] + m_borderWidth;
		}
		m_updatingKids = false;
		updateBorderShapes();
	}

	private static float chip(float budget, float desiredVal)
	{
		return fmin(fmax(0.0f, budget), fmax(0.0f, desiredVal));
	}

	private void updateBorderShapes()
	{
		if (!extBordersHidden)
		{
			// update external borders:
			// top border
			sfRectangleShape_setPosition(m_divBorders[0], sfVector2f(0.0f, 0.0f));
			sfRectangleShape_setSize(m_divBorders[0],
				sfVector2f(size.x, m_borderWidth));
			// bottom border
			sfRectangleShape_setPosition(m_divBorders[2], sfVector2f(0.0f, size.y - m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[2],
				sfVector2f(size.x, m_borderWidth));
			// left border
			sfRectangleShape_setPosition(m_divBorders[1], sfVector2f(0.0f, m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[1],
				sfVector2f(m_borderWidth, size.y - 2 * m_borderWidth));
			// right border
			sfRectangleShape_setPosition(m_divBorders[3], sfVector2f(size.x - m_borderWidth, m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[3],
				sfVector2f(m_borderWidth, size.y - 2 * m_borderWidth));
		}
		// update inter-child borders
		auto newBorderSize = dimVec(m_borderWidth, m_children[0].size[odim]).tosf;
		int offset = externalBorder;
		foreach (i, sfBorderRect; m_cellBorders)
		{
			offset += m_children[i].size[dim];
			vec2i newBorderPos = dimVec(offset, externalBorder);
			sfRectangleShape_setPosition(sfBorderRect, newBorderPos.tosf);
			sfRectangleShape_setSize(sfBorderRect, newBorderSize);
			offset += m_borderWidth;
		}
	}

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

	protected void onBeforeChildrenDraw(Window wnd, long usecsDelta) {}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (!extBordersHidden)
			foreach (rect; m_divBorders)
				sfRenderWindow_drawRectangleShape(wnd.wnd, rect, &m_sfRst);
		foreach (rect; m_cellBorders)
			sfRenderWindow_drawRectangleShape(wnd.wnd, rect, &m_sfRst);
		onBeforeChildrenDraw(wnd, usecsDelta);
		foreach (child; m_children)
			child.draw(wnd, usecsDelta);
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (super.getFromPoint(evt, x, y))
		{
			if (m_children.length == 0)
				return this;
			int offset = dim == 0 ? x - position.x : y - position.y;
			int cursor = externalBorder;
			foreach (kid; m_children)
			{
				auto check = kid.getFromPoint(evt, x, y);
				if (check && !check.mouseTransparent)
					return check;
				cursor += kid.size[dim] + m_borderWidth;
				if (cursor >= offset)
					return this;
			}
			return this;
		}
		else
			return null;
	}
}

Div hDiv(GuiElement[] children) { return new Div(DivType.HORZ, children); }
Div vDiv(GuiElement[] children) { return new Div(DivType.VERT, children); }