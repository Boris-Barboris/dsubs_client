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
module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_common.event;

import dsubs_client.core.utils;
import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.gui.manager;
import dsubs_client.input.router;


/// Layout policy used by layout managers.
enum LayoutType: byte
{
	FIXED,		/// element has fixed size
	CONTENT,	/// element size is dictated by it's content (used in textbox)
	FRACT,		/// element takes fraction of space, left after FIXED elements
	GREEDY,		/// element tries to fill all available space in the container
}

enum Axis: byte
{
	X = 0,	/// horizontal
	Y = 1,	/// vertical
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: IInputReceiver
{
	private
	{
		// layout parameters
		vec2i m_position;	// absolute position on the window
		vec2i m_size;		// absolute size

		/** parent viewport.
		If null, no intersection is performed.
		We use it separately instead of simply consulting parent
		element's viewport as a means of optimisation. Only
		scrollbar is actually setting it atm. */
		const(vec4i)* m_parentViewport = null;

		// if m_layoutType is FRACT, this is the fraction to use
		float m_fraction = 0.0f;
	}

	/// cached viewport rectangle
	protected vec4i m_viewport;
	private LayoutType m_layoutType = LayoutType.GREEDY;

	final @property ref const(vec4i) viewport() const { return m_viewport; }

	private GuiElement m_parent;	// layout manager of this element.

	this()
	{
		m_sfRst.blendMode = sfBlendAlpha;
		m_sfRect = sfRectangleShape_create();
		// Most elements don't have borders, and they don't manage them.
		sfRectangleShape_setOutlineThickness(m_sfRect, 0.0f);
		m_backgroundColor = sfTransparent;
	}

	/* The destructor for the super class automatically gets called when
	the destructor ends. There is no way to call the super destructor explicitly. */
	~this()
	{
		sfRectangleShape_destroy(m_sfRect);
	}

	final @property inout(GuiElement) parent() inout { return m_parent; }

	final @property GuiElement parent(GuiElement rhs)
	{
		return m_parent = rhs;
	}

	// Called by child when it's layout-related parameters have changed
	void childChanged(GuiElement child) {}

	mixin GetSet!(vec2i, "position", "updatePosition();");

	final vec2f center() const
	{
		return vec2f(
			position.x + size.x / 2.0f,
			position.y + size.y / 2.0f
		);
	}

	final @property vec2i size() const { return m_size; }

	@property vec2i size(vec2i rhs)
	{
		assert(rhs.x >= 0 && rhs.y >= 0);
		m_size = rhs;
		if ((m_layoutType == LayoutType.FIXED || m_layoutType == LayoutType.CONTENT) &&
				m_parent)
		{
			m_parent.childChanged(this);
		}
		updateSize();
		return m_size;
	}

	/// same as size setter, but sets layout to fixed
	@property vec2i fixedSize(vec2i rhs)
	{
		m_layoutType = LayoutType.FIXED;
		size = rhs;
		return m_size;
	}

	mixin FinalGetSet!(const(vec4i)*, "parentViewport", "updateViewport();");

	/// when layoutType is FRACT, this is what is used to detrmine element size
	final @property float fraction() const { return m_fraction; }

	/// sets layoutType to fration
	final @property float fraction(float rhs)
	{
		assert(rhs >= 0.0f);
		m_fraction = rhs;
		layoutType = LayoutType.FRACT;
		return m_fraction;
	}

	final @property LayoutType layoutType() const { return m_layoutType; }

	@property LayoutType layoutType(LayoutType rhs)
	{
		m_layoutType = rhs;
		if (m_parent)
			m_parent.childChanged(this);
		return m_layoutType;
	}

	/** Called by parent when it wants so set fixedDim axis size to fixedDimSize
	but wants the element to set the other dimention according to it's content size.
	Returns content size. */
	package int fitContent(Axis fixedDim, int fixedDimSize)
	{
		assert(m_layoutType == LayoutType.CONTENT);
		Axis contentDim = cast(Axis)(fixedDim ^ 1);	// xor 1 flips the bit
		if (fixedDimSize < 0)
			return m_size[contentDim];
		m_size[fixedDim] = fixedDimSize;
		m_size[contentDim] = doFitContent(fixedDim, contentDim);
		updateSize();
		if ((m_layoutType == LayoutType.FIXED || m_layoutType == LayoutType.CONTENT) &&
				m_parent)
		{
			m_parent.childChanged(this);
		}
		return m_size[contentDim];
	}

	/// This function should actually implement scaling by content.
	protected int doFitContent(Axis fixedDim, Axis contentDim)
	{
		return m_size[contentDim];
	}

	//
	// rendering stuff
	//

	protected sfRenderStates m_sfRst;		// stores transform
	private sfRectangleShape* m_sfRect;	// background rectangle

	private sfColor m_backgroundColor;

	mixin FinalGetSet!(sfColor, "backgroundColor",
		"sfRectangleShape_setFillColor(m_sfRect, rhs); backgroundVisible = true;");

	/// set to true in order to render background
	bool backgroundVisible = false;

	@property sfTransform sftransform() const { return m_sfRst.transform; }

	protected void updatePosition()
	{
		updateViewport();
		m_sfRst.transform = sfTransform_Identity;
		sfTransform_translate(&m_sfRst.transform, m_position.x, m_position.y);
	}

	protected void updateSize()
	{
		updateViewport();
		sfRectangleShape_setSize(m_sfRect, m_size.tosf);
	}

	protected void updateViewport()
	{
		if (m_parentViewport)
			m_viewport = clampViewport(m_parentViewport);
		else
			m_viewport = vec4i(m_position.x, m_position.y, m_size.x, m_size.y);
	}

	final VecT clampInsideRect(VecT)(VecT pos, VecT boxSize = VecT(0, 0)) const
	{
		pos.x = clamp(pos.x, m_position.x, m_position.x + m_size.x - boxSize.x);
		pos.y = clamp(pos.y, m_position.y, m_position.y + m_size.y - boxSize.y);
		return pos;
	}

	/// return intersection between rhs and this element's rectangle
	private vec4i clampViewport(const(vec4i)* rhs) const
	{
		vec4i res;
		res[0] = min(max((*rhs)[0], m_position.x), m_position.x + m_size.x);
		res[1] = min(max((*rhs)[1], m_position.y), m_position.y + m_size.y);
		int parentRight = (*rhs)[0] + (*rhs)[2];
		int parentBottom = (*rhs)[1] + (*rhs)[3];
		int childRight = max(res[0], min(m_position.x + m_size.x, parentRight));
		int childBottom = max(res[1], min(m_position.y + m_size.y, parentBottom));
		res[2] = max(0, childRight - res[0]);
		res[3] = max(0, childBottom - res[1]);
		return res;
	}

	/// If true, in the start of draw call, element will set windos's scissor test state
	/// to this element's rectange, clamped to parent's viewport.
	bool enableScissorTest = true;

	void draw(Window wnd, long usecsDelta)
	{
		if (enableScissorTest)
			sfRenderWindow_setScissor(wnd.wnd, m_viewport.tosf);
		if (backgroundVisible)
			sfRenderWindow_drawRectangleShape(wnd.wnd, m_sfRect, &m_sfRst);
	}

	//
	// IInputReceiver interface implementation
	//

	// Example implementation
	HandleResult handleKeyboard(Window wnd, const sfEvent* evt)
	{
		switch (evt.type)
		{
			case (sfEvtKeyPressed):
				onKeyPressed(cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtKeyReleased):
				onKeyReleased(cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtTextEntered):
				onTextEntered(cast(const sfTextEvent*) evt);
				break;
			default:
				assert(0, "can't handle non-keyboard event here");
		}
		return HandleResult(false);
	}

	HandleResult handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, float delta)
	{
		if (btn >= 0)
		{
			if (evt.type == sfEvtMouseButtonPressed)
				onMouseDown(x, y, btn);
			if (evt.type == sfEvtMouseButtonReleased)
				onMouseUp(x, y, btn);
		}
		else if (delta != 0)
			onMouseScroll(x, y, delta);
		else
			onMouseMove(x, y);
		return HandleResult(mouseTransparent);
	}

	void handleMouseEnter(IInputReceiver oldOwner)
	{
		onMouseEnter(oldOwner);
	}

	void handleMouseLeave(IInputReceiver newOwner)
	{
		onMouseLeave(newOwner);
	}

	// focuses
	mixin Readonly!(bool, "kbFocused");
	void handleKbFocusGain()
	{
		assert(!m_kbFocused);
		m_kbFocused = true;
		onKbFocusGain();
	}
	void handleKbFocusLoss()
	{
		assert(m_kbFocused);
		m_kbFocused = false;
		onKbFocusLoss();
	}
	mixin Readonly!(bool, "mouseFocused");
	void handleMouseFocusGain()
	{
		assert(!m_mouseFocused);
		m_mouseFocused = true;
		onMouseFocusGain();
	}
	void handleMouseFocusLoss()
	{
		assert(m_mouseFocused);
		m_mouseFocused = false;
		onMouseFocusLoss();
	}

	// focus manipulation methods

	final void requestKbFocus()
	{
		InputRouter.kbFocused = this;
	}

	final void returnKbFocus()
	{
		if (m_kbFocused)
			InputRouter.kbFocused = null;
	}

	final void requestMouseFocus()
	{
		InputRouter.mouseFocused = this;
	}

	final void returnMouseFocus()
	{
		if (m_mouseFocused)
			InputRouter.mouseFocused = null;
	}

	//
	// GUI-manager specifics
	//

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (rectContainsPoint(x, y))
			return this;
		return null;
	}

	/// Returns true if base element rectangle contains the point
	final bool rectContainsPoint(int x, int y) const
	{
		return ((x >= m_position.x && x < m_position.x + m_size.x) &&
			(y >= m_position.y && y < m_position.y + m_size.y));
	}

	/// whether the element is transparent for mouse events
	bool mouseTransparent = true;

	// gui manager will query panels and seek first non-mouse-transparent
	// element wich is placed under cursor.
	package GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiElement interceptor = getFromPoint(evt, x, y);
		if (interceptor)
			return GuiRouteResult(interceptor, interceptor.mouseTransparent);
		else
			return GuiRouteResult(null, true);
	}

	/// Called by manager or layout engine when this element leaves the screen
	void onHide()
	{
		returnMouseFocus();
		returnKbFocus();
	}

	// events for users to subscribe to
	Event!(void delegate(IInputReceiver oldOwner)) onMouseEnter;
	Event!(void delegate(IInputReceiver newOwner)) onMouseLeave;
	Event!(void delegate()) onMouseFocusGain;
	Event!(void delegate()) onKbFocusGain;
	Event!(void delegate()) onMouseFocusLoss;
	Event!(void delegate()) onKbFocusLoss;
	Event!(void delegate(int x, int y)) onMouseMove;
	Event!(void delegate(int x, int y, sfMouseButton btn)) onMouseDown;
	Event!(void delegate(int x, int y, sfMouseButton btn)) onMouseUp;
	Event!(void delegate(int x, int y, float delta)) onMouseScroll;
	Event!(void delegate(const sfKeyEvent* evt)) onKeyPressed;
	Event!(void delegate(const sfKeyEvent* evt)) onKeyReleased;
	Event!(void delegate(const sfTextEvent* evt)) onTextEntered;
}


/// Create a transparent greedy-sized GuiElement
GuiElement filler()
{
	return new GuiElement();
}

/// Create a transparent GuiElement of fixed size
GuiElement filler(int size)
{
	GuiElement r = new GuiElement();
	r.fixedSize = vec2i(size, size);
	return r;
}

/// Create a transparent GuiElement of fractional size
GuiElement filler(float fract)
{
	GuiElement r = new GuiElement();
	r.fraction = fract;
	return r;
}