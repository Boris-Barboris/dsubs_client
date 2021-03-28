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
module dsubs_client.render.camera;

import std.conv;
import std.math;

import gfm.math.funcs;
public import gfm.math.vector;
import gfm.math.matrix;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import dsubs_client.lib.sfml;
import dsubs_common.event;
import dsubs_common.math.angles: clampAngle;


/// 2D-camera class, specializes on relative, iterative
/// transformations, caused by camera panning.
class Camera2D
{
	protected
	{
		// transformation from world-space to screen-space
		mat3x3d m_mat;	// from world to screen space...
		mat3x3d m_imat;	// and it's inverse, from screen to world space
		// camera focus in world space
		vec2d m_center;
		// rotation in world space. 0 - North, Up is parallel to world Y axis.
		// Positive angle - counter-clockwise. Radians.
		double m_rotation;
		// zoom. 1 - 1 unit in world space takes one pixel on the screen.
		// 2.0 - 2 pixels.
		double m_zoom;

		vec2ui m_screenSize;

		// sfml-scpecific implementation
		sfView* m_sfView;

		bool m_dirty = false;
		bool m_inverseY;
	}

	this(vec2ui screenSize = vec2ui(640, 480), bool inverseY = true)
	{
		m_sfView = sfView_create();
		m_inverseY = inverseY;
		fromComponents(vec2d(0, 0), 0, 1, screenSize);
	}

	~this()
	{
		sfView_destroy(m_sfView);
	}

	protected void rebuild()
	{
		m_dirty = false;
		mat3x3d res = mat3x3d.translation(-m_center);
		res = mat3x3d.rotateZ(-m_rotation) * res;
		// screen Y is inversed relative to world Y, hence the minus
		res = mat3x3d.scaling(vec2d(m_zoom, m_inverseY ? -m_zoom : m_zoom)) * res;
		m_mat = mat3x3d.translation(vec2d(m_screenSize) / 2.0) * res;
		m_imat = m_mat.inverse();
		// update sfml view
		sfView_setCenter(m_sfView,
			sfVector2f(m_center.x, m_inverseY ? -m_center.y : m_center.y));
		sfView_setRotation(m_sfView, -degrees(m_rotation));
		sfView_setSize(m_sfView, m_screenSize.tosf);
		sfView_zoom(m_sfView, 1.0 / m_zoom);
	}

	final @property sfView* view()
	{
		if (m_dirty)
			rebuild();
		return m_sfView;
	}

	final @property ref const(mat3x3d) world2screen()
	{
		if (m_dirty)
			rebuild();
		return m_mat;
	}

	final @property ref const(mat3x3d) screen2world()
	{
		if (m_dirty)
			rebuild();
		return m_imat;
	}

	vec2d transform2screen(vec2d world)
	{
		vec3d homog = vec3d(world.x, world.y, 1.0);
		vec3d rs = world2screen * homog;
		return vec2d(rs.x / rs.z, rs.y / rs.z);
	}

	vec2d transform2world(vec2d screen)
	{
		vec3d homog = vec3d(screen.x, screen.y, 1.0);
		vec3d rs = screen2world * homog;
		return vec2d(rs.x / rs.z, rs.y / rs.z);
	}

	final @property vec2d center() const { return m_center; }

	final @property vec2d center(vec2d rhs)
	{
		m_dirty = true;
		return m_center = rhs;
	}

	final @property double zoom() const { return m_zoom; }

	final @property double zoom(double rhs)
	{
		m_dirty = true;
		return m_zoom = rhs;
	}

	final @property vec2ui screenSize() const { return m_screenSize; }

	final @property vec2ui screenSize(vec2ui rhs)
	{
		m_dirty = true;
		return m_screenSize = rhs;
	}

	final @property double rotation() const { return m_rotation; }

	final @property double rotation(double rhs)
	{
		m_dirty = true;
		return m_rotation = clampAngle(rhs);
	}

	/** Pan camera by rotated, but not scaled translation vector
	For example, if shift=(1.0, 0.0), this method pans camera center
	towards right hand by 1 world-space unit. */
	void pan(vec2d shift)
	{
		vec3d homog = vec3d(shift.x, shift.y, 1.0);
		vec3d rs = mat3x3d.rotateZ(m_rotation) * homog;
		m_center += vec2d(rs.x / rs.z, rs.y / rs.z);
		m_dirty = true;
	}

	void fromComponents(vec2d center, double rotation, double zoom, vec2ui screen)
	{
		m_center = center;
		m_rotation = rotation;
		m_zoom = zoom;
		m_screenSize = screen;
		rebuild();
	}
}


void testCamera2D()
{
	Camera2D camera = new Camera2D();
	vec2d center = camera.transform2screen(vec2d(0.0, 0.0));
	assert(abs(center.x - 320) < 1);
	assert(abs(center.y - 240) < 1);
	vec2d left_top = camera.transform2world(vec2d(0.0, 0.0));
	assert(abs(left_top.x + 320) < 1);
	assert(abs(left_top.y - 240) < 1);
	camera.zoom = 2.0;
	vec2d left = camera.transform2screen(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
	camera.rotation = PI_2;
	left = camera.transform2screen(vec2d(-10.0, 0.0));
	assert(abs(left.x - 320) < 1);
	assert(abs(left.y - 220) < 1);
	camera.pan(vec2d(10.0, 10.0));
	left = camera.transform2screen(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
}
