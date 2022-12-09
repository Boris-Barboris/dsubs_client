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
module dsubs_client.game.entities;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.traits: EnumMembers;
import std.utf;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.messages;
import dsubs_common.event;

import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game: Game;
import dsubs_client.render.shapes;
import dsubs_client.render.worldmanager;
import dsubs_client.math.transform;

import dsubs_client.game.kinetic;


class Propulsor
{
	mixin Readonly!(Transform, "transform");
	mixin Readonly!(const(PropulsorTemplate*), "tmpl");

	protected ConvexShape m_shape;

	float targetThrottle = 0.0f;

	this(EntityManager man, string propName)
	{
		m_transform = new Transform();
		m_tmpl = man.m_propTemplates[propName];
		m_shape = man.m_propulsorShapes[propName];
	}

	void update(CameraContext camCtx, long usecsDelta) {}
	abstract void renderBack(Window wnd);
	abstract void renderFront(Window wnd);
}


final class ScrewPropulsor: Propulsor
{
	private
	{
		ubyte m_bladeCount;
		float m_rotorAngle = 0.0;
		float m_angVel = 0.0;
		float m_flankRps;
		float m_throttleSpd;
		Transform m_rotTransform;
	}

	this(EntityManager man, string propName, ubyte bladeCount, float flankRps, float throttleSpd, bool inverse = false)
	{
		super(man, propName);
		m_bladeCount = bladeCount;
		m_flankRps = flankRps;
		if (inverse)
			m_flankRps = -m_flankRps;
		m_throttleSpd = throttleSpd;
		m_rotTransform = new Transform();
		transform.addChild(m_rotTransform);

		m_blades.length = m_bladeCount;
		float step = 2.0 * PI / m_bladeCount;
		float angle = m_rotorAngle;
		for (int i = 0; i < m_bladeCount; i++)
		{
			m_blades[i] = Blade(angle, cos(angle), sin(angle));
			angle += step;
		}
	}

	private struct Blade
	{
		float angle;
		float bladeCos;
		float bladeSin;
	}

	private Blade[] m_blades;

	override void update(CameraContext camCtx, long usecsDelta)
	{
		m_angVel = cmove(m_angVel, m_flankRps * targetThrottle * 2 * PI,
			fabs(m_flankRps) * m_throttleSpd * 2 * PI, usecsDelta / 1e6);
		double delta = m_angVel * 1e-6 * usecsDelta;
		m_rotorAngle += delta;
		m_rotorAngle = clampAngle(m_rotorAngle);
		foreach (ref blade; m_blades)
		{
			double newAngle = clampAngle(blade.angle + delta);
			blade = Blade(newAngle, cos(newAngle), sin(newAngle));
		}
		// we need to start from the blade wich is the deepest one
		sort!((a, b) => a.bladeSin < b.bladeSin)(m_blades);
	}

	override void renderBack(Window wnd)
	{
		foreach (ref blade; m_blades)
		{
			if (blade.bladeSin >= 0.0)
				break;
			m_rotTransform.scale = vec2d(blade.bladeCos, 1.0);
			m_shape.render(wnd, m_rotTransform.world);
		}
	}

	override void renderFront(Window wnd)
	{
		foreach (ref blade; m_blades)
		{
			if (blade.bladeSin < 0.0)
				continue;
			m_rotTransform.scale = vec2d(blade.bladeCos, 1.0);
			m_shape.render(wnd, m_rotTransform.world);
		}
	}
}


final class PumpPropulsor: Propulsor
{
	private double m_angVel = 0.0;

	this(EntityManager man, string propName)
	{
		super(man, propName);
	}

	override void renderBack(Window wnd) {}

	override void renderFront(Window wnd)
	{
		m_shape.render(wnd, transform.world);
	}
}


private Propulsor createPropulsor(EntityManager man, string propName, bool inverse)
{
	auto tmpl = man.m_propTemplates[propName];
	if (tmpl.type == PropulsorType.screw)
		return new ScrewPropulsor(man, propName, tmpl.bladeCount, tmpl.flankRps,
			tmpl.throttleSpd, inverse);
	else
		return new PumpPropulsor(man, propName);
}


final class AmmoRoom
{
	this(int id)
	{
		m_id = id;
	}

	private
	{
		int m_id;
		int[string] m_weaponCounts;
	}

	@property int id() const { return m_id; }
	@property ref const(int[string]) weaponCounts() const { return m_weaponCounts; }

	void updateFromFullState(AmmoRoomFullState newState)
	{
		m_weaponCounts = newState.toWeaponCountDict();
		onStateUpdate(this);
	}

	Event!(void delegate(AmmoRoom room)) onStateUpdate;

	int getWeaponCount(string wpnName) const { return m_weaponCounts.get(wpnName, 0); }
}


final class Tube
{
	this(Transform2D subTrans, MountPoint mount, AmmoRoom room, int id, TubeType tubeType)
	{
		m_transform = new Transform2D();
		m_transform.rotation = mount.rotation;
		m_transform.position = mount.mountCenter.to!vec2d;
		subTrans.addChild(m_transform);
		m_room = room;
		m_fullState.tubeId = id;
		m_tubeType = tubeType;
	}

	private
	{
		AmmoRoom m_room;
		TubeFullState m_fullState;
		TubeType m_tubeType;
		Transform2D m_transform;

		// cached limits of current weapon parameters
		MinMax m_marchSpeedLimits;
		MinMax m_activeSpeedLimits;
		MinMax m_activationRangeLimits;
		const(WeaponParamDescSearchPatterns)* m_searchPatternDesc;
		const(WeaponSensorMode)[] m_availableSensorModes;
	}

	@property Transform2D transform() { return m_transform; }

	// no need to encapsulate
	WeaponParamValue[WeaponParamType] weaponParams;

	@property AmmoRoom room() { return m_room; }

	@property const
	{
		int id() { return m_fullState.tubeId; }
		string loadedWeapon() { return m_fullState.loadedWeapon; }
		string desiredWeapon() { return m_fullState.desiredWeapon; }
		TubeType tubeType() { return m_tubeType; }
		TubeState currentState() { return m_fullState.currentState; }
		TubeState desiredState() { return m_fullState.desiredState; }
		string wireGuidanceId() { return m_fullState.wireGuidanceId; }
		bool wireGuidanceActive() { return m_fullState.wireGuidanceActive; }
		string wireGuidedWeaponName() { return m_fullState.wireGuidedWeaponName; }
	}

	@property void marchSpeed(float rhs)
	{
		assert(!isNaN(rhs));
		WeaponParamValue val;
		val.type = WeaponParamType.marchSpeed;
		val.speed = rhs;
		weaponParams[val.type] = val;
	}

	@property MinMax marchSpeedLimits() const { return m_marchSpeedLimits; }
	@property MinMax activeSpeedLimits() const { return m_activeSpeedLimits; }
	@property MinMax activationRangeLimits() const { return m_activationRangeLimits; }

	@property const(WeaponParamDescSearchPatterns)* searchPatternDesc() const
	{
		return m_searchPatternDesc;
	}

	@property WeaponSearchPattern[] availableSearchPatterns() const
	{
		return [EnumMembers!WeaponSearchPattern].filter!(
			sp => sp & searchPatternDesc.availablePatterns).array;
	}

	@property const(WeaponSensorMode)[] availableSensorModes() const
	{
		return m_availableSensorModes;
	}

	@property void activeSpeed(float rhs)
	{
		assert(!isNaN(rhs));
		WeaponParamValue val;
		val.type = WeaponParamType.activeSpeed;
		val.speed = rhs;
		weaponParams[val.type] = val;
	}

	@property void activationRange(float rhs)
	{
		assert(!isNaN(rhs));
		WeaponParamValue val;
		val.type = WeaponParamType.activationRange;
		val.range = rhs;
		weaponParams[val.type] = val;
	}

	@property void course(float rhs)
	{
		assert(!isNaN(rhs));
		WeaponParamValue val;
		val.type = WeaponParamType.course;
		val.course = rhs;
		weaponParams[val.type] = val;
	}

	@property WeaponSensorMode sensorMode() const
	{
		return weaponParams[WeaponParamType.sensorMode].sensorMode;
	}

	@property void sensorMode(WeaponSensorMode rhs)
	{
		WeaponParamValue val;
		val.type = WeaponParamType.sensorMode;
		val.sensorMode = rhs;
		weaponParams[val.type] = val;
	}

	@property void searchPattern(WeaponSearchPattern rhs)
	{
		WeaponParamValue val;
		val.type = WeaponParamType.searchPattern;
		val.searchPattern = rhs;
		weaponParams[val.type] = val;
	}

	@property const (WeaponTemplate)* currentWeaponTemplate() const
	{
		return Game.entityManager.weaponTemplates.get(m_fullState.loadedWeapon, null);
	}

	void updateFromFullState(TubeFullState newState)
	{
		if (m_fullState.loadedWeapon != newState.loadedWeapon)
		{
			weaponParams.clear();
			if (m_tubeType == TubeType.standard && newState.loadedWeapon)
			{
				// set default parameter values from the weapon template description
				const WeaponTemplate* wtpl =
					Game.entityManager.weaponTemplates[newState.loadedWeapon];
				foreach (ref const WeaponParamDesc desc; wtpl.paramDescs)
				{
					switch (desc.type)
					{
						case WeaponParamType.marchSpeed:
							m_marchSpeedLimits = desc.speedRange;
							marchSpeed = desc.speedRange.max;
							break;
						case WeaponParamType.activeSpeed:
							m_activeSpeedLimits = desc.speedRange;
							activeSpeed = desc.speedRange.max;
							break;
						case WeaponParamType.activationRange:
							m_activationRangeLimits = desc.activationRange;
							activationRange = desc.activationRange.min;
							break;
						case WeaponParamType.sensorMode:
							m_availableSensorModes = [EnumMembers!WeaponSensorMode].
								filter!(sm => sm & desc.sensorModes).array;
							WeaponSensorMode firstAvailableMode =
								[EnumMembers!WeaponSensorMode].find!(mode =>
									mode & desc.sensorModes).front();
							sensorMode = firstAvailableMode;
							break;
						case WeaponParamType.searchPattern:
							m_searchPatternDesc = &desc.searchPatterns;
							WeaponSearchPattern firstAvailablePattern =
								[EnumMembers!WeaponSearchPattern].find!(pat =>
									pat & desc.searchPatterns.availablePatterns).front();
							searchPattern = firstAvailablePattern;
							break;
						default:
							break;
					}
				}
			}
		}
		m_fullState = newState;
		onStateUpdate(this);
	}

	void sendLaunchRequest()
	{
		assert(currentState == TubeState.open);
		assert(loadedWeapon != null);
		Game.ciccon.sendMessage(cast(immutable) CICLaunchTubeReq(
			LaunchTubeReq(id, loadedWeapon, weaponParams.values)));
	}

	void sendDesiredWeaponRequest(string newWeapon)
	{
		if (desiredWeapon != newWeapon)
			Game.ciccon.sendMessage(cast(immutable) CICLoadTubeReq(
				LoadTubeReq(id, newWeapon)));
	}

	void sendDesiredStateRequest(TubeState newState)
	{
		assert(isStableState(newState));
		if (newState != desiredState)
			Game.ciccon.sendMessage(cast(immutable) CICSetTubeStateReq(
				SetTubeStateReq(id, newState)));
	}

	Event!(void delegate(Tube tube)) onStateUpdate;
}


final class WireGuidedWeapon: WorldRenderable
{
	mixin Readonly!(const(WeaponTemplate*), "tmpl");
	mixin Readonly!(string, "wireGuidanceId");

	// no need to encapsulate
	WeaponParamValue[WeaponParamType] weaponParams;
	WireGuidanceFullState lastState;

	@property int tubeId() const
	{
		return m_tube.id;
	}

	private
	{
		KinematicTrace m_trace;
		Tube m_tube;
		// cached limits for parameters
		MinMax m_marchSpeedLimits;
		MinMax m_activeSpeedLimits;
		const(WeaponParamDescSearchPatterns)* m_searchPatternDesc;
		const(WeaponSensorMode)[] m_availableSensorModes;
	}

	// no model atm
	override void render(Window wnd) {}

	this(EntityManager man, string wireGuidanceId, Tube tube,
		WeaponParamValue[] weaponParamValues)
	{
		assert(tube.wireGuidedWeaponName, "tube.wireGuidedWeaponName is null");
		m_tmpl = man.weaponTemplates[tube.wireGuidedWeaponName];
		m_wireGuidanceId = wireGuidanceId;
		m_tube = tube;
		foreach (wp; weaponParamValues)
		{
			// filter-out uncontrollable-by-wire parameters
			if (m_tmpl.wireControlledParams & wp.type)
			{
				weaponParams[wp.type] = wp;
			}
		}
		trace("Built a wire-guided weapon object with params: ", weaponParams);
	}

	void updateKinematics(ref const KinematicSnapshot snap)
	{
		m_trace.appendSnapshot(snap);
	}

	/// returns true if the snapshot was written to res
	bool getLastSnapshot(out KinematicSnapshot res) const
	{
		if (m_trace.canInterpolate)
		{
			res = m_trace.mostRecent;
			return true;
		}
		return false;
	}

	/// returns true if the snapshot was written to res
	bool getInterpolatedSnapshot(out KinematicSnapshot res) const
	{
		if (m_trace.canInterpolate)
		{
			res = m_trace.result;
			return true;
		}
		return false;
	}

	@property MinMax marchSpeedLimits() const { return m_marchSpeedLimits; }
	@property MinMax activeSpeedLimits() const { return m_activeSpeedLimits; }

	@property WeaponSearchPattern[] availableSearchPatterns() const
	{
		return [EnumMembers!WeaponSearchPattern].filter!(
			sp => sp & m_searchPatternDesc.availablePatterns).array;
	}

	@property const(WeaponSensorMode)[] availableSensorModes() const
	{
		return m_availableSensorModes;
	}

	override void update(CameraContext camCtx, long usecsDelta)
	{
		if (m_trace.canInterpolate)
		{
			m_trace.moveForward(usecsDelta);
			// update transform from the trace
			transform.position = m_trace.result.position;
			transform.rotation = m_trace.result.rotation;
		}
	}
}



final class AttachedWire
{
	enum sfColor WIRE_COLOR = sfColor(180, 180, 180, 255);

	private
	{
		/// attachment transform
		Transform2D m_trans;
		int m_index;
		Submarine m_sub;
		WireTrace m_trace;
		__gshared LineShape g_lineShape;
	}

	this(Submarine sub, int index, MountPoint mount)
	{
		m_sub = sub;
		m_index = index;
		m_trans = new Transform2D();
		sub.transform.addChild(m_trans);
		m_trans.position = mount.mountCenter.to!vec2d;
		m_trace.attachTransform = m_trans;
		m_trace.attachTrace = &m_sub.trace;
		if (g_lineShape is null)
			g_lineShape = new LineShape(vec2d(0, 0), vec2d(0, 0), WIRE_COLOR, 0.45f);
	}

	void appendSnapshot(const WireSnapshot snap)
	{
		m_trace.appendSnapshot(snap);
	}

	@property Transform2D attachTransform() { return m_trans; }

	@property Submarine submarine() { return m_sub; }

	void update(usecs_t delta)
	{
		if (m_trace.canInterpolate)
			m_trace.moveForward(delta);
	}

	void render(Window wnd)
	{
		if (!m_trace.canInterpolate || m_trace.result.points.length == 0)
			return;
		for (size_t i = 0; i < m_trace.result.points.length; i++)
		{
			vec2d pos1, pos2;
			pos1 = m_trace.result.points[i].position;
			if (i < m_trace.result.points.length - 1)
				pos2 = m_trace.result.points[i + 1].position;
			else
				pos2 = m_trans.wposition;
			g_lineShape.setPoints(pos1, pos2);
			g_lineShape.render(wnd);
		}
	}
}


final class Submarine: WorldRenderable
{
	mixin Readonly!(const(SubmarineTemplate*), "tmpl");

	private Propulsor[] m_propulsors;
	private ConvexShape[] m_shapes;
	private KinematicTrace trace;
	private AttachedWire[] m_wires;

	@property AttachedWire[] wires() { return m_wires; }

	private AmmoRoom[int] m_ammoRooms;
	private Tube[int] m_tubes;

	AmmoRoom ammoRoom(int roomId) { return m_ammoRooms[roomId]; }
	Tube tube(int tubeId) { return m_tubes[tubeId]; }
	auto ammoRoomRange() { return m_ammoRooms.byValue; }
	auto tubeRange() { return m_tubes.byValue; }

	Tube getTubeByWireGuidanceId(string wireGuidanceId)
	{
		foreach (tube; m_tubes.byValue)
		{
			if (tube.wireGuidanceId == wireGuidanceId)
				return tube;
		}
		return null;
	}

	float targetCourse = 0.0f;
	private float m_targetThrottle = 0.0f;

	@property float targetThrottle() const { return m_targetThrottle; }
	@property float targetThrottle(float tgt)
	{
		m_targetThrottle = tgt;
		foreach (p; m_propulsors)
			p.targetThrottle = tgt;
		return tgt;
	}

	this(EntityManager man, string hullName, string propName)
	{
		m_tmpl = man.m_submarineTemplates[hullName];
		m_shapes = man.m_submarineShapes[hullName];
		setPropulsor(man, propName);
		foreach (const AmmoRoomTemplate at; m_tmpl.ammoRooms)
			m_ammoRooms[at.id] = new AmmoRoom(at.id);
		foreach (const TubeTemplate tt; m_tmpl.tubes)
			m_tubes[tt.id] = new Tube(this.transform,
				tt.mount, m_ammoRooms[tt.roomId], tt.id, tt.type);
		// build wires
		foreach (i, hyhroTemplate; m_tmpl.hydrophones.filter!(
				h => h.type == HydrophoneType.towed).array)
			m_wires ~= new AttachedWire(this, i.to!int, hyhroTemplate.mount);
	}

	void updateKinematics(ref const KinematicSnapshot snap)
	{
		trace.appendSnapshot(snap);
	}

	void updateWireKinematics(const WireSnapshot[] wireSnaps)
	{
		assert(wireSnaps.length == m_wires.length);
		foreach (i, wire; m_wires)
			wire.appendSnapshot(wireSnaps[i]);
	}

	/// returns true if the snapshot was written to res
	bool getLastSnapshot(out KinematicSnapshot res) const
	{
		if (trace.canInterpolate)
		{
			res = trace.mostRecent;
			return true;
		}
		return false;
	}

	/// returns true if the snapshot was written to res
	bool getInterpolatedSnapshot(out KinematicSnapshot res) const
	{
		if (trace.canInterpolate)
		{
			res = trace.result;
			return true;
		}
		return false;
	}

	override void update(CameraContext camCtx, long usecsDelta)
	{
		if (trace.canInterpolate)
		{
			trace.moveForward(usecsDelta);
			// update transform from the trace
			transform.position = trace.result.position;
			transform.rotation = trace.result.rotation;
		}
		foreach (prop; m_propulsors)
			prop.update(camCtx, usecsDelta);
		foreach (wire; m_wires)
			wire.update(usecsDelta);
	}

	override void render(Window wnd)
	{
		foreach (prop; m_propulsors)
			prop.renderBack(wnd);
		for (int i = 0; i < m_tmpl.elevatedHullShapeIdx; i++)
			m_shapes[i].render(wnd, transform.world);
		foreach (prop; m_propulsors)
			prop.renderFront(wnd);
		foreach (wire; m_wires)
			wire.render(wnd);
		for (int i = m_tmpl.elevatedHullShapeIdx; i < m_shapes.length; i++)
			m_shapes[i].render(wnd, transform.world);
	}

	/// Remove existing propulsor and set a new one
	void setPropulsor(EntityManager man, string propName)
	{
		// unset existing propulsors
		foreach (p; m_propulsors)
			transform.removeChild(p.transform);
		m_propulsors.length = 0;
		// setup propulsors
		foreach (i, mount; m_tmpl.propulsionMounts)
		{
			Propulsor p = createPropulsor(man, propName, i % 2 == 1);
			p.transform.scale = vec2d(mount.scale, mount.scale);
			p.transform.rotation = mount.rotation;
			p.transform.position = mount.mountCenter.tod;
			p.targetThrottle = m_targetThrottle;
			transform.addChild(p.transform);
			m_propulsors ~= p;
		}
	}
}


/// Collection of shapes and templates, created from the entity database
final class EntityManager
{
	private ConvexShape[string] m_propulsorShapes;
	private ConvexShape[][string] m_submarineShapes;

	mixin Readonly!(const(PropulsorTemplate)*[string], "propTemplates");
	mixin Readonly!(const(SubmarineTemplate)*[string], "submarineTemplates");
	mixin Readonly!(const(WeaponTemplate)*[string], "weaponTemplates");

	/// construct shape collection from entity database
	this(const(EntityDb) db)
	{
		info("building entity manager from serialized database");
		foreach (prop; db.propulsors)
		{
			auto ptr = new PropulsorTemplate;
			*ptr = cast(PropulsorTemplate) prop;
			m_propTemplates[prop.name] = ptr;
			m_propulsorShapes[prop.name] = fromPolygon(prop.model);
		}
		foreach (sub; db.controllableSubs)
		{
			auto ptr = new SubmarineTemplate;
			*ptr = cast(SubmarineTemplate) sub;
			m_submarineTemplates[sub.name] = ptr;
			m_submarineShapes[sub.name] =
				sub.hullModel.map!(a => fromPolygon(a)).array;
		}
		foreach (wpn; db.weapons)
		{
			auto ptr = new WeaponTemplate;
			*ptr = cast(WeaponTemplate) wpn;
			m_weaponTemplates[wpn.name] = ptr;
		}
	}

	private ConvexShape fromPolygon(const(ConvexPolygon) p)
	{
		return new ConvexShape(
			cast(const(sfVector2f)[]) p.points,
			cast(sfColor) p.fillColor,
			cast(sfColor) p.borderColor,
			p.borderWidth);
	}
}
