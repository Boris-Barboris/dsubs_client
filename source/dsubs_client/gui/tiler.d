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
module dsubs_client.gui.tiler;

import std.algorithm;
import std.conv: to;
import std.experimental.logger;
import std.math;

import derelict.sfml2.graphics;
import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.element;
import dsubs_client.gui.div;


interface ITilerChoiceProvider
{
	bool isSplitPossible();
	void proposeSplittingChoice(int x, int y, void delegate(GuiElement) onSelect);
	void handleChildRemoved(GuiElement child);
}


/// Linear div, but internal borders can be dragged by mouse.
/// Behaves in proportional manner, maintaining relative fractions
/// of it's children. Additionally, when in edit mode, each child can be split in
/// 4 directions, by either extending this TilerDiv or ehclosing the cild in
/// another new TiledDiv, spanning in separate direction. In such a way recursive
/// tree of rectangular elements can be created.
class TilerDiv: Div
{
	private enum Quadrant: ubyte
	{
		center,
		upper,
		left,
		right,
		lower
	}

	private
	{
		// Borders are draggable in edit mode only.
		// When it's false, it's just a standard div.
		bool m_editMode;
		sfColor m_hoverBorderColor = sfColor(255, 150, 150, 255);
		sfColor m_pressedBorderColor = sfColor(255, 25, 25, 255);

		// is some border being dragged?
		bool m_dragging;
		int m_prevMousePos;
		// if the border is being dragged, this is it's index
		int m_pressedBorderIdx = -1;
		// if the border is being hovered over, this is it's index
		int m_hoveredBorderIdx = -1;
		// if mouse is hovering over a child, this is it's index...
		int m_hoverChildIdx = -1;
		// if mouse is this far from the center of a child, assume the quadrant
		// is "center".
		float m_centerQuadrantPart = 0.15f;
		// and this is where it's hovering
		Quadrant m_hoverChildQuadrant;


		ITilerChoiceProvider m_choiceProvider;
		sfColor m_splitDirHintColor = sfColor(255, 150, 150, 100);
		sfRectangleShape* m_splitDirRectangle;

		bool[GuiElement] m_unremovableChildren;
	}

	// If choiceProvider is null, splitting functionality will be disabled, and
	// only interior border dragging will be active
	this(DivType divType, ITilerChoiceProvider choiceProvider, GuiElement[] kids)
	{
		m_borderColor = sfColor(100, 100, 100, 255);
		foreach (kid; kids)
		{
			kid.layoutType = LayoutType.FRACT;
			if (kid.fraction == 0.0f)
				kid.fraction = 1.0f;
		}
		m_choiceProvider = choiceProvider;
		super(divType, kids);
		borderWidth = 5;
		m_splitDirRectangle = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_splitDirRectangle, 0.0f);
		sfRectangleShape_setFillColor(m_splitDirRectangle, m_splitDirHintColor);
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseMove += &handleMouseMove;
		onMouseLeave += &handleMouseLeave;
	}

	final @property bool editMode() const { return m_editMode; }

	final @property bool editMode(bool rhs)
	{
		m_editMode = rhs;
		if (!rhs)
		{
			m_dragging = false;
			returnMouseFocus();
			m_pressedBorderIdx = m_hoveredBorderIdx = m_hoverChildIdx = -1;
			mouseTransparent = true;
		}
		else
			mouseTransparent = false;
		updateBorderColor();
		// for each child that is also TilerDiv update it's edit mode
		foreach (child; children)
		{
			TilerDiv childTilerDiv = cast(TilerDiv) child;
			if (childTilerDiv)
				childTilerDiv.editMode = rhs;
		}
		return m_editMode;
	}

	void markChildUnremovable(GuiElement child)
	{
		m_unremovableChildren[child] = true;
	}

	void markChildRemovable(GuiElement child)
	{
		m_unremovableChildren.remove(child);
	}

	final @property float centerQuadrantPart() const { return m_centerQuadrantPart; }

	final @property void centerQuadrantPart(float rhs)
	{
		assert(rhs >= 0.0f && rhs <= 1.0f);
		m_centerQuadrantPart = rhs;
	}

	override void updateBorderColor()
	{
		super.updateBorderColor();
		if (!m_editMode)
			return;
		foreach (i, brd; m_cellBorders)
		{
			if (m_pressedBorderIdx == i)
				sfRectangleShape_setFillColor(brd, m_pressedBorderColor);
			else if (m_hoveredBorderIdx == i)
				sfRectangleShape_setFillColor(brd, m_hoverBorderColor);
		}
	}

	private void updateSplitRectangle()
	{
		if (m_editMode && m_choiceProvider !is null && m_hoverChildIdx >= 0)
		{
			vec2i hoveredChildSize = children[m_hoverChildIdx].size;
			vec2i hoveredChildRelPos = children[m_hoverChildIdx].position - this.position;
			final switch (m_hoverChildQuadrant)
			{
				case Quadrant.center:
					vec2f splitDirSize = 2.0f * vec2f(
						hoveredChildSize.x * m_centerQuadrantPart,
						hoveredChildSize.y * m_centerQuadrantPart);
					hoveredChildRelPos += vec2i(
						to!int(round(
							(hoveredChildSize.x - splitDirSize.x) / 2.0f)),
						to!int(round(
							(hoveredChildSize.y - splitDirSize.y) / 2.0f)));
					sfRectangleShape_setSize(m_splitDirRectangle, splitDirSize.tosf);
					sfRectangleShape_setPosition(m_splitDirRectangle,
						hoveredChildRelPos.tosf);
					break;
				case Quadrant.left:
					vec2i rectSize = vec2i(hoveredChildSize.x / 2, hoveredChildSize.y);
					sfRectangleShape_setSize(m_splitDirRectangle, rectSize.tosf);
					sfRectangleShape_setPosition(m_splitDirRectangle,
						hoveredChildRelPos.tosf);
					break;
				case Quadrant.upper:
					vec2i rectSize = vec2i(hoveredChildSize.x, hoveredChildSize.y / 2);
					sfRectangleShape_setSize(m_splitDirRectangle, rectSize.tosf);
					sfRectangleShape_setPosition(m_splitDirRectangle,
						hoveredChildRelPos.tosf);
					break;
				case Quadrant.right:
					vec2i rectSize = vec2i(hoveredChildSize.x / 2, hoveredChildSize.y);
					vec2i rectPos = vec2i(hoveredChildRelPos.x + rectSize.x,
						hoveredChildRelPos.y);
					sfRectangleShape_setSize(m_splitDirRectangle, rectSize.tosf);
					sfRectangleShape_setPosition(m_splitDirRectangle,
						rectPos.tosf);
					break;
				case Quadrant.lower:
					vec2i rectSize = vec2i(hoveredChildSize.x, hoveredChildSize.y / 2);
					vec2i rectPos = vec2i(hoveredChildRelPos.x,
						hoveredChildRelPos.y + rectSize.y);
					sfRectangleShape_setSize(m_splitDirRectangle, rectSize.tosf);
					sfRectangleShape_setPosition(m_splitDirRectangle,
						rectPos.tosf);
					break;
			}
		}
	}

	override GuiElement setChild(GuiElement newChild, size_t idx)
	{
		newChild.layoutType = LayoutType.FRACT;
		if (newChild.fraction == 0.0f)
			newChild.fraction = 1.0f;
		return super.setChild(newChild, idx);
	}

	override void addChild(GuiElement newChild, size_t idx)
	{
		newChild.layoutType = LayoutType.FRACT;
		if (newChild.fraction == 0.0f)
			newChild.fraction = 1.0f;
		return super.addChild(newChild, idx);
	}

	private @property void dragging(bool rhs)
	{
		if (rhs != m_dragging)
		{
			if (rhs)
			{
				assert(m_pressedBorderIdx >= 0 &&
					m_pressedBorderIdx < m_cellBorders.length);
				sfRectangleShape_setFillColor(
					m_cellBorders[m_pressedBorderIdx],
					m_pressedBorderColor);
				requestMouseFocus();
			}
			else
			{
				assert(m_pressedBorderIdx >= 0 &&
					m_pressedBorderIdx < m_cellBorders.length);
				sfRectangleShape_setFillColor(
					m_cellBorders[m_pressedBorderIdx],
					m_borderColor);
				returnMouseFocus();
				onDragEnd(m_pressedBorderIdx);
				m_pressedBorderIdx = -1;	// not sure if here is the right place
			}
		}
		m_dragging = rhs;
	}

	private void moveBorderByDelta(int borderIdx, int delta)
	{
		m_updatingKids = true;
		float sumOfFractions = fold!((a, b) => a + b.fraction)(children, 0.0f);
		int pureBudget = pureChildrenBudget();
		if (pureBudget <= 0)
			return;
		float fractPerPixel = sumOfFractions / pureBudget;
		float fract1 = children[borderIdx].fraction;
		float fract2 = children[borderIdx + 1].fraction;
		// one child's fraction must be decreased by this, the other - increased
		float fractDelta = delta * fractPerPixel;
		// clamp to prevent negative fraction of childer after the drag
		if (fractDelta < 0.0f)
			fractDelta = fmax(-fract1, fractDelta);
		else
			fractDelta = fmin(fract2, fractDelta);
		children[borderIdx].fraction = fract1 + fractDelta;
		children[borderIdx + 1].fraction = fract2 - fractDelta;
		updateChildren();
	}

	private void handleMouseMove(int x, int y)
	{
		if (!m_editMode)
			return;
		int relx = x - position.x;
		int rely = y - position.y;
		int relVal = (fixedAxis == Axis.X ? rely : relx);
		int delta = relVal - m_prevMousePos;
		m_prevMousePos = relVal;
		if (m_dragging)
		{
			// border must be moved by delta
			assert(m_pressedBorderIdx >= 0 &&
				   m_pressedBorderIdx < m_cellBorders.length &&
				   m_pressedBorderIdx + 1 < children.length);
			moveBorderByDelta(m_pressedBorderIdx, delta);
		}
		else
		{
			// hover detection and m_hoveredBorderIdx calculation
			int oldHoverIdx = m_hoveredBorderIdx;
			m_hoveredBorderIdx = -1;
			foreach (i, sfBorderRect; m_cellBorders)
			{
				sfVector2f sfPos = sfRectangleShape_getPosition(sfBorderRect);
				sfVector2f sfSize = sfRectangleShape_getSize(sfBorderRect);
				if ((relx >= sfPos.x && relx < sfPos.x + sfSize.x) &&
					(rely >= sfPos.y && rely < sfPos.y + sfSize.y))
				{
					// border is hit
					m_hoveredBorderIdx = i.to!int;
					break;
				}
			}
			if (oldHoverIdx != m_hoveredBorderIdx)
				updateBorderColor();
			if (m_choiceProvider is null)
				return;
			// hover over child detection m_hoverChildIdx
			oldHoverIdx = m_hoverChildIdx;
			Quadrant oldQuadrant = m_hoverChildQuadrant;
			m_hoverChildIdx = -1;
			// no need to look for child since we already know that mouse is over
			// border.
			if (m_hoveredBorderIdx == -1)
			{
				foreach (i, child; children)
				{
					if (whatQuadrant(child, x, y, m_hoverChildQuadrant))
					{
						// we have found the child
						m_hoverChildIdx = i.to!int;
						break;
					}
				}
			}
			if (oldHoverIdx != m_hoverChildIdx || oldQuadrant != m_hoverChildQuadrant)
				updateSplitRectangle();
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		// draw split hint rectangle on top of a child
		if (m_editMode && m_hoverChildIdx >= 0)
		{
			sfRenderWindow_setScissor(wnd.wnd, viewport.tosf);
			sfRenderWindow_drawRectangleShape(wnd.wnd, m_splitDirRectangle, &m_sfRst);
		}
	}

	// returns false if not in child's rectangle
	private bool whatQuadrant(GuiElement child, int x, int y, ref Quadrant qrant)
	{
		if (child.rectContainsPoint(x, y))
		{
			vec2f center = child.center;
			vec2i size = child.size;
			if (fabs(center.x - x) <= m_centerQuadrantPart * size.x &&
				fabs(center.y - y) <= m_centerQuadrantPart * size.y)
			{
				qrant = Quadrant.center;
				return true;
			}
			if (x > center.x)
			{
				if (fabs(y - center.y) <= (x - center.x))
					qrant = Quadrant.right;
				else
				{
					if (y > center.y)
						qrant = Quadrant.lower;
					else
						qrant = Quadrant.upper;
				}
			}
			else
			{
				if (fabs(y - center.y) <= (center.x - x))
					qrant = Quadrant.left;
				else
				{
					if (y > center.y)
						qrant = Quadrant.lower;
					else
						qrant = Quadrant.upper;
				}
			}
			return true;
		}
		else
			return false;
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (m_choiceProvider is null || !m_editMode)
			return super.getFromPoint(evt, x, y);
		if (this.GuiElement.getFromPoint(evt, x, y))
		{
			if (children.length == 0)
				return this;
			int offset = dim == 0 ? x - position.x : y - position.y;
			int cursor = externalBorder;
			foreach (kid; children)
			{
				TilerDiv childTiler = cast(TilerDiv) kid;
				if (childTiler)
				{
					auto check = childTiler.getFromPoint(evt, x, y);
					if (check)
						return check;
				}
				cursor += kid.size[dim] + borderWidth;
				if (cursor >= offset)
					return this;
			}
			return this;
		}
		else
			return null;
	}

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		if (m_hoveredBorderIdx == -1)
			return;
		m_pressedBorderIdx = m_hoveredBorderIdx;
		dragging = true;
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		dragging = false;
		// FIXME: not proper button-like event handling but it will do
		if (m_hoverChildIdx != -1 && m_choiceProvider !is null)
		{
			Quadrant qr = m_hoverChildQuadrant;
			int childIdx = m_hoverChildIdx;
			// trace("Click on quadrant: ", m_hoverChildQuadrant);
			if (qr == Quadrant.center)
			{
				// TODO: center click was performed, we must either remove this
				// element from the tiledDiv or if it was the last element -
				// remove from the parent tilerDiv
				GuiElement childToRemove = children[childIdx];
				if (childToRemove !in m_unremovableChildren)
				{
					if (children.length >= 2)
					{
						// trace("removing child");
						GuiElement removedChild = this.removeChildAt(childIdx);
						splitFractionAmongChildren(this, removedChild.fraction);
						m_choiceProvider.handleChildRemoved(removedChild);
					}
					else
					{
						// we only remove the last child if the parent is actually
						// a Div.
						Div parentDiv = cast(Div) this.parent;
						if (parentDiv)
						{
							// trace("removing itself from parent");
							parentDiv.removeChild(this);
							splitFractionAmongChildren(parentDiv, this.fraction);
							// child is not actually removed from this particular div
							// but it is still effectively removed from the hierarchy
							m_choiceProvider.handleChildRemoved(children[0]);
						}
						else
							trace("Removing last element is impossible");
					}
				}
			}
			else
			{
				if (m_choiceProvider.isSplitPossible())
				{
					m_choiceProvider.proposeSplittingChoice(x, y, (newChild) {
						this.splitChild(newChild, childIdx, qr);
					});
				}
				// else
				// 	trace("Split is impossible");
			}
		}
	}

	private static void splitFractionAmongChildren(Div container,
		float removedChildFract)
	{
		if (container.children.length == 0)
			return;
		float removedBorderFractionAsIfChild;
		if (container.fixedAxis == Axis.Y)
		{
			removedBorderFractionAsIfChild = cast(float) container.borderWidth /
				container.size.x;
		}
		else
		{
			removedBorderFractionAsIfChild = cast(float) container.borderWidth /
				container.size.y;
		}
		float delta = (removedChildFract + removedBorderFractionAsIfChild) /
			container.children.length;
		// account for one removed border
		foreach (child; container.children)
			child.fraction = child.fraction + delta;
	}

	private void splitChild(GuiElement newChild, int childIdx, Quadrant splitDirection)
	{
		// trace("childIdx is splitting: ", childIdx, " ", splitDirection);
		assert(childIdx >= 0 && childIdx < children.length);
		// TODO actually split the child in the direction of a quadrant
		if (fixedAxis == Axis.Y)
		{
			switch (splitDirection)
			{
				case Quadrant.left:
					// old child moves right
					splitFractions(newChild, childIdx);
					addChild(newChild, childIdx);
					break;
				case Quadrant.right:
					// new child moves right
					splitFractions(newChild, childIdx);
					addChild(newChild, childIdx + 1);
					break;
				case Quadrant.upper:
					// Tree direction change. Child at childIdx must be replaced
					// with new TilerDiv.
					buildOrthogonalCopyAndEmplate(newChild, childIdx, 1);
					break;
				case Quadrant.lower:
					// Tree direction change. Child at childIdx must be replaced
					// with new TilerDiv.
					buildOrthogonalCopyAndEmplate(newChild, childIdx, 0);
					break;
				default:
					return;
			}
		}
		else
		{
			switch (splitDirection)
			{
				case Quadrant.upper:
					// old child moves right
					splitFractions(newChild, childIdx);
					addChild(newChild, childIdx);
					break;
				case Quadrant.lower:
					// new child moves right
					splitFractions(newChild, childIdx);
					addChild(newChild, childIdx + 1);
					break;
				case Quadrant.left:
					// Tree direction change. Child at childIdx must be replaced
					// with new TilerDiv.
					buildOrthogonalCopyAndEmplate(newChild, childIdx, 1);
					break;
				case Quadrant.right:
					// Tree direction change. Child at childIdx must be replaced
					// with new TilerDiv.
					buildOrthogonalCopyAndEmplate(newChild, childIdx, 0);
					break;
				default:
					return;
			}
		}
	}

	// split fractions equally, so that the split will not affect other cells
	private void splitFractions(GuiElement newChild, int childIdx)
	{
		GuiElement oldChild = children[childIdx];
		float newBorderFractionInOldChild = 0.0f;
		if (fixedAxis == Axis.Y)
		{
			if (borderWidth < oldChild.size.x)
				newBorderFractionInOldChild = cast(float) borderWidth / oldChild.size.x;
		}
		else
		{
			if (borderWidth < oldChild.size.y)
				newBorderFractionInOldChild = cast(float) borderWidth / oldChild.size.y;
		}
		newChild.layoutType = LayoutType.FRACT;
		newChild.fraction = oldChild.fraction * (1.0f - newBorderFractionInOldChild) /
			2.0f;
		oldChild.fraction = oldChild.fraction * (1.0f - newBorderFractionInOldChild) /
			2.0f;
	}

	private TilerDiv buildOrthogonalCopyAndEmplate(GuiElement newChild,
		int emplaceChildIdx, size_t addOldChildToCopyAtIdx)
	{
		DivType orthType = (fixedAxis == Axis.Y ? DivType.VERT : DivType.HORZ);
		TilerDiv newTiler = new TilerDiv(orthType, m_choiceProvider, [newChild]);
		newTiler.borderWidth = borderWidth;
		newTiler.borderColor = borderColor;
		newTiler.editMode = editMode;

		GuiElement oldChild = setChild(newTiler, emplaceChildIdx);
		newTiler.fraction = oldChild.fraction;
		oldChild.fraction = newChild.fraction;
		newTiler.addChild(oldChild, addOldChildToCopyAtIdx);
		return newTiler;
	}

	override void handleMouseFocusLoss()
	{
		super.handleMouseFocusLoss();
		dragging = false;
	}

	private void handleMouseLeave(IInputReceiver newOwner)
	{
		m_hoveredBorderIdx = -1;
		m_hoverChildIdx = -1;
		updateBorderColor();
	}

	Event!(void delegate(int borderIdx)) onDragEnd;
}


TilerDiv hTilerDiv(ITilerChoiceProvider choiceProvider, GuiElement[] children)
{
	return new TilerDiv(DivType.HORZ, choiceProvider, children);
}

TilerDiv vTilerDiv(ITilerChoiceProvider choiceProvider, GuiElement[] children)
{
	return new TilerDiv(DivType.VERT, choiceProvider, children);
}
