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
module dsubs_client.render.shapes;

import std.conv: to;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.math.transform;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;


abstract class Shape
{
	protected sfRenderStates m_rendStates;

	this()
	{
		m_rendStates.blendMode = sfBlendAlpha;
	}

	void render(Window wnd);
	void render(Window wnd, const mat3x3d trans);
	void render(Window wnd, const sfTransform trans);
}


/// Unordered composite of other shapes
final class ShapeComposite: Shape
{
	private Shape[] m_shapes;

	this(Shape[] shapes)
	{
		m_shapes = shapes;
	}

	override void render(Window wnd)
	{
		foreach (shape; m_shapes)
			shape.render(wnd);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		foreach (shape; m_shapes)
			shape.render(wnd, trans);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		foreach (shape; m_shapes)
			shape.render(wnd, trans);
	}
}


/// Convex polygon shape, backed by SFML ConvexShape. Vertices are immutable.
final class ConvexShape: Shape
{
	private sfConvexShape* m_shape;

	this(const(sfVector2f)[] points, sfColor fillColor,
		sfColor borderColor, float borderWidth)
	{
		m_shape = sfConvexShape_create();
		sfConvexShape_setPointCount(m_shape, points.length);
		for (int i = 0; i < points.length; i++)
			sfConvexShape_setPoint(m_shape, i, points[i]);
		sfConvexShape_setFillColor(m_shape, fillColor);
		sfConvexShape_setOutlineColor(m_shape, borderColor);
		sfConvexShape_setOutlineThickness(m_shape, borderWidth);
	}

	~this()
	{
		sfConvexShape_destroy(m_shape);
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}
}


/// Symmetric polygon, backed by SFML circle.
final class CircleShape: Shape
{
	private sfCircleShape* m_shape;

	this(float radius = 10.0f, int vcount = 30, sfColor color = sfWhite,
		float borderW = 1.0f)
	{
		m_shape = sfCircleShape_create();
		sfCircleShape_setRadius(m_shape, radius);
		sfCircleShape_setPointCount(m_shape, vcount);
		sfCircleShape_setFillColor(m_shape, sfTransparent);
		sfCircleShape_setOutlineColor(m_shape, color);
		sfCircleShape_setOutlineThickness(m_shape, borderW);
		sfCircleShape_setOrigin(m_shape, sfVector2f(radius, radius));
	}

	~this()
	{
		sfCircleShape_destroy(m_shape);
	}

	@property float radius() const
	{
		return sfCircleShape_getRadius(m_shape);
	}

	@property void radius(float rhs)
	{
		sfCircleShape_setRadius(m_shape, rhs);
		sfCircleShape_setOrigin(m_shape, sfVector2f(rhs, rhs));
	}

	@property float rotation() const
	{
		return sfCircleShape_getRotation(m_shape);
	}

	@property void rotation(float rhs)
	{
		sfCircleShape_setRotation(m_shape, rhs);
	}

	@property vec2f center() const
	{
		return cast(vec2f) sfCircleShape_getPosition(m_shape);
	}

	@property void center(vec2f rhs)
	{
		sfCircleShape_setPosition(m_shape, rhs.tosf);
	}

	@property size_t vertexCount() const
	{
		return sfCircleShape_getPointCount(m_shape);
	}

	@property void vertexCount(int rhs)
	{
		sfCircleShape_setPointCount(m_shape, rhs);
	}

	@property sfColor fillColor() const
	{
		return sfCircleShape_getFillColor(m_shape);
	}

	@property void fillColor(sfColor rhs)
	{
		sfCircleShape_setFillColor(m_shape, rhs);
	}

	@property sfColor borderColor() const
	{
		return sfCircleShape_getOutlineColor(m_shape);
	}

	@property void borderColor(sfColor rhs)
	{
		sfCircleShape_setOutlineColor(m_shape, rhs);
	}

	@property float borderWidth() const
	{
		return sfCircleShape_getOutlineThickness(m_shape);
	}

	@property void borderWidth(float rhs)
	{
		sfCircleShape_setOutlineThickness(m_shape, rhs);
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}
}


final class RectangleShape: Shape
{
	private sfRectangleShape* m_shape;

	this(vec2f size, sfColor borderCol,
		sfColor fillColor = sfTransparent, float borderW = 1.0f)
	{
		m_shape = sfRectangleShape_create();
		sfRectangleShape_setSize(m_shape, size.tosf);
		sfRectangleShape_setOutlineColor(m_shape, borderCol);
		sfRectangleShape_setFillColor(m_shape, fillColor);
		sfRectangleShape_setOutlineThickness(m_shape, borderW);
	}

	@property vec2f position() const
	{
		return cast(vec2f) sfRectangleShape_getPosition(m_shape);
	}

	@property void position(vec2f rhs)
	{
		sfRectangleShape_setPosition(m_shape, rhs.tosf);
	}

	@property vec2f center() const
	{
		return position + 0.5f * size;
	}

	@property void center(vec2f rhs)
	{
		position = rhs - 0.5f * size;
	}

	@property vec2f size() const
	{
		return cast(vec2f) sfRectangleShape_getSize(m_shape);
	}

	@property void size(vec2f rhs)
	{
		sfRectangleShape_setSize(m_shape, rhs.tosf);
	}

	@property sfColor fillColor() const
	{
		return sfRectangleShape_getFillColor(m_shape);
	}

	@property void fillColor(sfColor rhs)
	{
		sfRectangleShape_setFillColor(m_shape, rhs);
	}

	@property sfColor borderColor() const
	{
		return sfRectangleShape_getOutlineColor(m_shape);
	}

	@property void borderColor(sfColor rhs)
	{
		sfRectangleShape_setOutlineColor(m_shape, rhs);
	}

	@property float borderWidth() const
	{
		return sfRectangleShape_getOutlineThickness(m_shape);
	}

	@property void borderWidth(float rhs)
	{
		sfRectangleShape_setOutlineThickness(m_shape, rhs);
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	~this()
	{
		sfRectangleShape_destroy(m_shape);
	}
}


/// Mutable variable-width line,
/// SFML rectangle under the hood. Has it's own transform.
final class LineShape: Shape
{
	private
	{
		sfRectangleShape* m_shape;
		Transform m_transform;
		vec2d m_p2;
	}

	@property Transform transform() { return m_transform; }

	this(vec2d p1, vec2d p2, sfColor color, float width = 1.0f, bool invertY = false)
	{
		m_transform = new Transform();
		m_shape = sfRectangleShape_create();
		sfRectangleShape_setFillColor(m_shape, color);
		sfRectangleShape_setOutlineThickness(m_shape, 0.0f);
		sfRectangleShape_setSize(m_shape, sfVector2f(1.0f, 1.0f));
		sfRectangleShape_setPosition(m_shape, sfVector2f(0.0f, -0.5f));
		if (invertY)
		{
			p1.y = -p1.y;
			p2.y = -p2.y;
		}
		rebuild(p1, p2, width);
	}

	~this()
	{
		sfRectangleShape_destroy(m_shape);
	}

	void setPoints(vec2d p1, vec2d p2, bool invertY = false)
	{
		if (invertY)
		{
			p1.y = -p1.y;
			p2.y = -p2.y;
		}
		rebuild(p1, p2, width);
	}

	@property void color(sfColor rhs)
	{
		sfRectangleShape_setFillColor(m_shape, rhs);
	}

	private void rebuild(vec2d p1, vec2d p2, float width)
	{
		m_transform.position = p1;
		m_p2 = p2;
		double rot = courseAngle(p2 - p1) + PI_2;
		if (!isNaN(rot))
			m_transform.rotation = rot;
		m_transform.scale = vec2d((p2 - p1).length, width);
	}

	@property double length() { return m_transform.scale.x; }

	/// Get base of the altitude from point 'from'. 'inside' is set to true if
	/// the base is between p1 and p2.
	vec2d getAltitudeBase(vec2d from, out bool inside, out double k)
	{
		// https://math.stackexchange.com/questions/1317578/how-to-find-the-coordinates-where-the-altitude-of-a-triangle-intersects-the-base#comment6169024_2674944
		vec2d A = m_transform.position;
		vec2d C = m_p2;
		vec2d B = from;
		vec2d D;
		k = ((B.x - A.x) * (C.x - A.x) + (B.y - A.y) * (C.y - A.y)) /
			(pow(C.x - A.x, 2) + pow(C.y - A.y, 2));
		D.x = A.x + k * (C.x - A.x);
		D.y = A.y + k * (C.y - A.y);
		inside = (k >= 0.0 && k <= 1.0);
		return D;
	}

	bool intersect(LineShape rhs, ref vec2d intersection)
	{
		vec2d a = m_transform.position;
		vec2d b = m_p2;
		vec2d c = rhs.m_transform.position;
		vec2d d = rhs.m_p2;
		vec2f intersectionPoint;
		bool res = get_line_intersection(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y,
			&intersectionPoint.x, &intersectionPoint.y);
		if (res)
			intersection = intersectionPoint.to!vec2d;
		return res;
	}

	// https://stackoverflow.com/a/1968345/3084875
	private static bool get_line_intersection(float p0_x, float p0_y, float p1_x, float p1_y,
		float p2_x, float p2_y, float p3_x, float p3_y, float *i_x, float *i_y)
	{
		float s1_x, s1_y, s2_x, s2_y;
		s1_x = p1_x - p0_x;     s1_y = p1_y - p0_y;
		s2_x = p3_x - p2_x;     s2_y = p3_y - p2_y;

		float s, t;
		s = (-s1_y * (p0_x - p2_x) + s1_x * (p0_y - p2_y)) / (-s2_x * s1_y + s1_x * s2_y);
		t = ( s2_x * (p0_y - p2_y) - s2_y * (p0_x - p2_x)) / (-s2_x * s1_y + s1_x * s2_y);

		if (s >= 0 && s <= 1 && t >= 0 && t <= 1)
		{
			// Collision detected
			if (i_x != null)
				*i_x = p0_x + (t * s1_x);
			if (i_y != null)
				*i_y = p0_y + (t * s1_y);
			return true;
		}

		return false; // No collision
	}

	@property float width() { return m_transform.scale.y; }

	@property void width(float rhs)
	{
		vec2d curScale = m_transform.scale;
		curScale.y = rhs;
		m_transform.scale = curScale;
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = m_transform.world.tosf;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = tosf(trans * m_transform.world);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = tosf(trans.togfm * m_transform.world);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}
}
