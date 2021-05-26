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
module dsubs_client.game.tacoverlay;

import std.algorithm: max, min, filter;
import std.conv: to;
import std.array: array;
import std.math;
import std.container.rbtree;
import std.experimental.logger;
import std.range;

import core.time;

import derelict.sfml2.graphics;

import dsubs_common.math;
import dsubs_common.mutstring;
import dsubs_common.api.entities;

import dsubs_client.common;
import dsubs_client.core.window;
import dsubs_client.render.shapes;
import dsubs_client.render.worldmanager;
import dsubs_client.math.transform;
import dsubs_client.input.router: IInputReceiver;
import dsubs_client.input.hotkeymanager: HotkeyManager, Modifier;
import dsubs_client.gui;
import dsubs_client.game;
import dsubs_client.game.waterfall;
import dsubs_client.game.sonardisp;
import dsubs_client.game.cic.messages;
import dsubs_client.game.tubeui;
import dsubs_client.game.entities;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.kinetic;
import dsubs_client.game.contacts;



/// Cache of pre-constructed shapes for overlay rendering
final class ContactOverlayShapeCahe
{
	this()
	{
		m_shapes[ContactType.unknown] = forContactTypeNew(ContactType.unknown);
		m_shapes[ContactType.environment] = forContactTypeNew(ContactType.environment);
		m_shapes[ContactType.submarine] = forContactTypeNew(ContactType.submarine);
		m_shapes[ContactType.weapon] = forContactTypeNew(ContactType.weapon);
		m_shapes[ContactType.decoy] = forContactTypeNew(ContactType.decoy);
		m_onHoverRect = new RectangleShape(vec2f(22.0f, 22.0f), sfWhite);
		m_onHoverRect.position = -vec2f(1, 1);
		m_posDataMainShape = new RectangleShape(vec2f(5, 5), sfRed);
		m_posDataOnHoverRect = new RectangleShape(vec2f(11.0f, 11.0f), sfWhite);
		m_posDataOnHoverRect.position = -vec2f(1, 1);
		m_wfRayDataMainShape = new RectangleShape(vec2f(2, 2), sfRed);
		m_wfRayDataOnHoverRect = new RectangleShape(vec2f(11.0f, 11.0f), sfWhite);
		m_wfRayDataOnHoverRect.position = -vec2f(1, 1);
		m_velCircle = new CircleShape(TacticalContactElement.ZERO_SPD_PIXEL_MARGIN,
			30, sfColor(255, 255, 255, 150), 6);
		m_tubeCircle = new CircleShape(10, 30, COLORS.tubeCircle, 3);
		m_velDragLine = new LineShape(vec2d(0, 0), vec2d(0, 0), sfColor(137, 182, 255, 255), 4);
		m_pastTrailLine = new LineShape(vec2d(0, 0), vec2d(0, 0),
			sfColor(232, 244, 63, 100), 3);
		m_dataTrailDelta = new LineShape(vec2d(0, 0), vec2d(0, 0),
			sfColor(255, 22, 154, 200), 2);
		m_shortestToSolution = new LineShape(vec2d(0, 0), vec2d(0, 0),
			sfColor(21, 216, 230, 200), 2);
		m_rayTracker = new LineShape(vec2d(0, 0), vec2d(0, 0),
			sfColor(117, 79, 255, 100), 1.0);
		m_rayChainLine = new LineShape(vec2d(0, 0), vec2d(0, 0),
			sfColor(255, 0, 0, 150), 1.0);
	}

	private
	{
		CircleShape[ContactType.max + 1] m_shapes;
	}

	mixin Readonly!(RectangleShape, "onHoverRect");
	mixin Readonly!(RectangleShape, "posDataMainShape");
	mixin Readonly!(RectangleShape, "posDataOnHoverRect");
	mixin Readonly!(RectangleShape, "wfRayDataMainShape");
	mixin Readonly!(RectangleShape, "wfRayDataOnHoverRect");
	mixin Readonly!(CircleShape, "velCircle");
	mixin Readonly!(CircleShape, "tubeCircle");
	mixin Readonly!(LineShape, "velDragLine");
	mixin Readonly!(LineShape, "pastTrailLine");
	mixin Readonly!(LineShape, "dataTrailDelta");
	mixin Readonly!(LineShape, "rayTracker");
	mixin Readonly!(LineShape, "rayChainLine");
	mixin Readonly!(LineShape, "shortestToSolution");

	// https://stackoverflow.com/a/8509802/3084875
	static sfColor rotateColor(sfColor color, float hue)
	{
		float U = cos(hue * PI / 180);
		float W = sin(hue * PI / 180);

		sfColor res;
		res.r = ((.299+.701*U+.168*W)*color.r
			+ (.587-.587*U+.330*W)*color.g
			+ (.114-.114*U-.497*W)*color.b).to!ubyte;
		res.g = ((.299-.299*U-.328*W)*color.r
			+ (.587+.413*U+.035*W)*color.g
			+ (.114-.114*U+.292*W)*color.b).to!ubyte;
		res.b = ((.299-.3*U+1.25*W)*color.r
			+ (.587-.588*U-1.05*W)*color.g
			+ (.114+.886*U-.203*W)*color.b).to!ubyte;
		res.a = color.a;
		return res;
	}

	LineShape rayDataLine(int sensorIdx, usecs_t sampleTime, usecs_t zeroFadeTime)
	{
		sfColor rayColor = dimRayColor(sensorIdx, sampleTime, zeroFadeTime);
		return new LineShape(vec2d(0, 0), vec2d(0, 0), rayColor, 0.5);
	}

	static sfColor dimRayColor(int sensorIdx, usecs_t sampleTime, usecs_t zeroFadeTime)
	{
		sfColor res = rotateColor(sfColor(155, 244, 66, 80), sensorIdx * -65);
		float age = (zeroFadeTime - sampleTime) / 1e6f;
		if (age > 0.0f)
		{
			float dimming = min(55.0f, age / 6.0f);
			res.a -= dimming.to!ubyte;
		}
		return res;
	}

	@property LineShape weaponProjectionLine()
	{
		return new LineShape(vec2d(0, 0), vec2d(0, 0),
			WeaponProjectionTrace.ACTIVE_COLOR, 2);
	}

	/// returns shared shape
	CircleShape forContactType(ContactType t)
	{
		return m_shapes[t];
	}

	/// builds new shape
	CircleShape forContactTypeNew(ContactType t)
	{
		final switch (t)
		{
			case ContactType.unknown:
				return new CircleShape(8.0f, 4, sfColor(244, 241, 66, 255), 2);
			case ContactType.environment:
				return new CircleShape(7.0f, 6, sfColor(107, 244, 65, 255), 2);
			case ContactType.submarine:
				return new CircleShape(8.0f, 12, sfColor(255, 132, 10, 255), 2);
			case ContactType.weapon:
				return new CircleShape(5.0f, 3, sfRed, 2);
			case ContactType.decoy:
				return new CircleShape(5.0f, 5, sfColor(152, 9, 255, 255), 2);
		}
	}
}


pragma(inline)
private ContactOverlayShapeCahe ctcOverlayCache()
{
	return Game.simState.contactOverlayShapeCache;
}

private __gshared vec2i g_dragOffset;


/// Overlay element that draws a rectange when the mouse hovers over it
class OverlayElementWithHover: OverlayElement
{
	this(Overlay owner)
	{
		super(owner);
		onMouseEnter += (o) { m_hovered = true; };
		onMouseLeave += (o) { m_hovered = false; };
	}

	protected
	{
		RectangleShape m_onHoverRect;
		bool m_hovered;
	}
}

/// Overlay element that is bound to ClientContactData.
class ContactDataOverlayElement: OverlayElementWithHover
{
	this(Overlay owner, ClientContactData* data)
	{
		m_data = data;
		super(owner);
	}

	mixin Readonly!(ClientContactData*, "data");

	@property ClientContact contact()
	{
		return Game.simState.contactManager.get(m_data.ctcId);
	}

	/// When the contact data updates from CIC message, this method is called;
	abstract void updateFromData();
}


/// Active sonar data sample on sonar display.
final class SonarDispContactDataElement: ContactDataOverlayElement
{
	this(SonarDisplay.SonarOverlay owner, ClientContactData* data, ClientContact contact)
	{
		assert(data.type == DataType.Position);
		assert(data.source.type == DataSourceType.ActiveSonar);
		super(owner, data);
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		// we need to calculate bearing and range relative to last ping source
		// in order to be able to draw it
		if (owner.outer.havePingSourcePosition)
			processNewPing(owner.outer.pingSourcePosition);
		updateFromContact(contact);

		onMouseDown += &processMouseDown;
		onMouseMove += &processMouseMove;
		onMouseUp += &processMouseUp;
	}

	private @property SonarDisplay.SonarOverlay owner()
	{
		return cast(SonarDisplay.SonarOverlay) super.owner;
	}

	override void updateFromData()
	{
		if (owner.outer.havePingSourcePosition)
			processNewPing(owner.outer.pingSourcePosition);
	}

	void updateFromContact(ClientContact contact)
	{
		m_mainShape = ctcOverlayCache.forContactType(contact.type);
		size = cast(vec2i) vec2f(2 * m_mainShape.radius + 4, 2 * m_mainShape.radius + 4);
		if (m_contactName is null)
		{
			m_contactName = new Label();
			m_contactName.enableScissorTest = false;
			m_contactName.fontSize = 15;
			m_contactName.content = contact.id.to!string;
			m_contactName.fontColor = sfRed;
			m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
				m_contactName.contentHeight + 2);
		}
	}

	override @property bool hidden() {
		return !m_initialized || super.hidden();
	}

	/// Rebuilds bearing and range for current ping source from ContactData
	void processNewPing(vec2d pingSourcePos)
	{
		returnMouseFocus();
		vec2d contactPos = data.data.position.contactPos;
		vec2d direction = contactPos - pingSourcePos;
		m_bearing = courseAngle(direction);
		m_range = direction.length;
		m_initialized = true;
	}

	private
	{
		/// True when m_bearing and range were initialized from ping source
		bool m_initialized;
		double m_bearing, m_range;
		CircleShape m_mainShape;
		Label m_contactName;
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2screenPos(vec2d(m_bearing, m_range));
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (m_hovered)
		{
			m_contactName.position = vec2i(position.x + size.x / 2 - m_contactName.size.x / 2,
				position.y + size.y + 2);
			m_onHoverRect.center = cast(vec2f) screenPos;
			m_onHoverRect.size = cast(vec2f) size;
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
		if (m_hovered)
			m_contactName.draw(wnd, usecsDelta);
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			m_dragging = true;
			g_dragOffset = vec2i(x, y) - position;
			requestMouseFocus();
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = commonContactContextMenu(
				Game.simState.contactManager.get(data.ctcId));
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
		if (btn == sfMouseLeft && m_dragging)
		{
			m_dragging = false;
			if (!m_panning)
				returnMouseFocus();
			requestDataUpdate();
		}
	}

	/// Send updated data to cic
	private void requestDataUpdate()
	{
		vec2d pingSource = owner.outer.pingSourcePosition;
		vec2d newWorldPos = pingSource + m_range * courseVector(m_bearing);
		usecs_t newTime = owner.outer.pingTime;
		ContactData updated = data.cdata;
		if (newTime != data.time)
			updated.id = -1;	// different time = new data sample
		updated.time = newTime;
		updated.data.position.contactPos = newWorldPos;
		Game.ciccon.sendMessage(immutable CICContactDataReq(updated));
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - g_dragOffset;
			vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
			// we now need to update bearing and range from screen-space position
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);
			m_bearing = newWorldCoord.x;
			m_range = newWorldCoord.y;
		}
	}
}


/// Overlay element in the header of waterfall display
final class HydrophoneTrackerElement: OverlayElementWithHover
{
	private
	{
		Label m_label;
		HydrophoneTracker m_tracker;
		float m_bearing;
	}

	@property Waterfall.TrackerOverlay towner() { return cast(Waterfall.TrackerOverlay) owner; }

	this(Waterfall.TrackerOverlay owner, HydrophoneTracker tracker)
	{
		m_tracker = tracker;
		super(owner);
		m_label = new Label();
		m_label.enableScissorTest = false;
		m_label.content = m_tracker.id.ctcId.to!string;
		m_label.fontSize = 16;
		m_label.fontColor = sfWhite;
		m_label.htextAlign = HTextAlign.CENTER;
		m_label.size = vec2i(m_label.contentWidth.to!int, m_label.contentHeight.to!int + 4);
		m_onHoverRect = new RectangleShape(cast(vec2f) m_label.size, sfWhite);
		size = m_label.size;

		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
	}

	void updateFromTracker(HydrophoneTracker ht)
	{
		m_tracker = ht;
		if (ht.state == TrackerState.inactive)
			m_label.fontColor = sfColor(150, 150, 150, 255);
		else
			m_label.fontColor = sfWhite;
		m_bearing = m_tracker.bearing;
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2screenPos(vec2d(m_bearing, 0));
		position = center2lu(screenPos);
		m_label.position = position;
		if (m_hovered)
		{
			m_onHoverRect.center = cast(vec2f) screenPos;
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_label.draw(wnd, usecsDelta);
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - g_dragOffset;
			vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
			// we now need to update bearing and range from screen-space position
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);
			m_bearing = newWorldCoord.x;
		}
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			m_dragging = true;
			g_dragOffset = vec2i(x, y) - position;
			requestMouseFocus();
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			Button[] buttons = commonContactContextMenu(
				Game.simState.contactManager.get(m_tracker.id.ctcId));
			Button dropTrackerBtn = builder(new Button()).fontSize(15).content("drop tracker").build();
			dropTrackerBtn.onClick +=
				{ Game.ciccon.sendMessage(immutable CICDropTrackerReq(m_tracker.id)); };
			ContextMenu menu = contextMenu(
					Game.guiManager,
					dropTrackerBtn ~ buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
		if (btn == sfMouseLeft && m_dragging)
		{
			m_dragging = false;
			if (!m_panning)
				returnMouseFocus();
			Game.ciccon.sendMessage(immutable CICUpdateTrackerReq(
				HydrophoneTracker(m_tracker.id, m_bearing)));
		}
	}
}


/// Main overlay of F1 screen
final class TacticalOverlay: Overlay
{

	alias ContactDataTimeTree = RedBlackTree!(ContactDataOverlayElement, (a, b) => a.data.time < b.data.time, true);

	private
	{
		CameraController m_camCtrl;
		int m_mousePrevX, m_mousePrevY;
		bool m_panned;	/// true when mouse has moved since RMB down
		TacticalContactElement m_selectedContact;
		ContactDataOverlayElement[int] m_selectedContactData;
		ContactDataTimeTree m_selectedContactDataByTime;
		OverlayElement[] m_scenarioElements;
		HoveredContactDescription m_hoverDesc;

		enum int HOVER_DESC_YSHIFT = 28;

		bool m_inMerge;
		ContactId m_mergeSourceId;
		TacticalContactElement m_mergeSourceElement;

		MapGrid m_mapGrid;

		// pings
		PingWaveCircleShape[int] m_sonarPings;
	}

	void registerPing(int sensorIdx)
	{
		PingWaveCircleShape oldPing = m_sonarPings.get(sensorIdx, null);
		if (oldPing)
		{
			remove(oldPing);
			m_sonarPings.remove(sensorIdx);
		}
		KinematicSnapshot lastSnap;
		bool gotSnap = Game.simState.playerSub.getLastSnapshot(lastSnap);
		assert(gotSnap);
		PingWaveCircleShape newPing = new PingWaveCircleShape(
			this, sensorIdx,
			Game.simState.playerSub.tmpl.sonar.maxDuration,
			lastSnap);
		m_sonarPings[sensorIdx] = newPing;
	}

	void removeOldPings()
	{
		PingWaveCircleShape[] pingsToRemove;
		foreach (kv_pair; m_sonarPings.byKeyValue)
		{
			if (kv_pair.value.finished)
				pingsToRemove ~= kv_pair.value;
		}
		foreach (PingWaveCircleShape shape; pingsToRemove)
		{
			m_sonarPings.remove(shape.sonarIdx);
			remove(shape);
		}
	}

	@property bool inMerge() const { return m_inMerge; }

	@property ContactId mergeSourceId() const { return m_mergeSourceId; }

	void startMerge(TacticalContactElement sourceElement, ContactId newMergeSource)
	{
		m_inMerge = true;
		m_mergeSourceId = newMergeSource;
		m_mergeSourceElement = sourceElement;
		Game.simState.gui.showMainHint(sourceElement, "Click on the contact to merge into",
			{ m_inMerge = false; m_mergeSourceElement = null; });
	}

	void cancelMerge()
	{
		assert(m_inMerge);
		assert(m_mergeSourceElement);
		Game.simState.gui.hideMainHint(m_mergeSourceElement);
		assert(!m_inMerge);
		assert(m_mergeSourceElement is null);
	}

	this(CameraController camCtrl)
	{
		m_camCtrl = camCtrl;
		m_selectedContactDataByTime = new ContactDataTimeTree();
		mouseTransparent = false;
		// mouse and keyboard handlers
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;

		m_hoverDesc = new HoveredContactDescription();

		m_mapGrid = new MapGrid(COLORS.mapGrid, 1.0f);
	}

	override void updatePosition()
	{
		super.updatePosition();
		m_hoverDesc.mainDiv.position = position + vec2i(size.x, HOVER_DESC_YSHIFT) -
			vec2i(m_hoverDesc.mainDiv.size.x, 0);
	}

	override void updateSize()
	{
		super.updateSize();
		m_hoverDesc.mainDiv.position = position + vec2i(size.x, HOVER_DESC_YSHIFT) -
			vec2i(m_hoverDesc.mainDiv.size.x, 0);
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			onPanStart(x, y);
			requestMouseFocus();
		}
	}

	override void onPanStart(int x, int y)
	{
		m_panned = false;
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			selectedContact = null;
			if (inMerge)
				cancelMerge();
		}
		if (btn == sfMouseRight)
		{
			returnMouseFocus();
			if (!m_panned)
			{
				// spawn context menu
				Button[] buttons;
				Button cmsBtn = builder(new Button()).fontSize(15).
					content("create manual contact").build();
				vec2d pos = screen2worldPos(vec2d(x, y));
				usecs_t atTime = Game.simState.extrapolatedServerTime;
				ContactDataUnion cdu;
				cdu.position = PositionData(pos);
				cmsBtn.onClick += {
					Game.ciccon.sendMessage(immutable CICCreateContactFromDataReq(
						'M',
						ContactData(
							-1, ContactId(), atTime,
							DataSource(DataSourceType.Manual, 0), DataType.Position,
							cdu)
					));
				};
				buttons ~= cmsBtn;
				vec2d dir = pos - Game.simState.playerSub.transform.wposition;
				if (dir.length > 1e-20)
				{
					float courseReq = courseAngle(dir);
					Button setCourseBtn = builder(new Button()).fontSize(15).
						content("set course towards").build();
					setCourseBtn.onClick += {
						Game.ciccon.sendMessage(CICCourseReq(courseReq));
					};
					buttons ~= setCourseBtn;
				}
				ContextMenu menu = contextMenu(
						Game.guiManager,
						buttons,
						Game.window.size,
						vec2i(x, y),
						20);
			}
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused)
			onPan(x, y);
	}

	override void onPan(int x, int y)
	{
		if (m_mousePrevX != x || m_mousePrevY != y)
			m_panned = true;	// we have moved the mouse
		m_camCtrl.onPan(x - m_mousePrevX, y - m_mousePrevY);
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseScroll(int x, int y, float delta)
	{
		m_camCtrl.onScroll(x, y, delta);
	}

	override vec2d world2screenPos(vec2d world)
	{
		return m_camCtrl.camera.transform2screen(world);
	}

	override double world2screenRot(double world)
	{
		return world - m_camCtrl.camera.rotation;
	}

	override vec2d screen2worldPos(vec2d screen)
	{
		return m_camCtrl.camera.transform2world(screen);
	}

	override double screen2worldRot(double screen)
	{
		return screen + m_camCtrl.camera.rotation;
	}

	override double world2screenLength(double world)
	{
		return world * m_camCtrl.camera.zoom;
	}

	override double screen2worldLength(double screen)
	{
		return screen / m_camCtrl.camera.zoom;
	}

	/// replace old set of map elements with the new set
	void updateScenarioElements(const(MapElement)[] mapElements)
	{
		foreach (OverlayElement el; m_scenarioElements)
			remove(el);
		m_scenarioElements.length = 0;
		foreach (const MapElement el; mapElements)
		{
			switch (el.type)
			{
				case MapElementType.circle:
					m_scenarioElements ~= new ScenarioCircleShape(this, el);
					break;
				case MapElementType.text:
					m_scenarioElements ~= new ScenarioTextShape(this, el);
					break;
				default:
					assert(0, "not supported element type");
			}
		}
	}

	@property TacticalContactElement selectedContact() { return m_selectedContact; }

	@property void selectedContact(TacticalContactElement rhs)
	{
		// we need to start drawing all data of this contact
		if (rhs is m_selectedContact)
			return;
		trace("setting owner to ", rhs);
		if (m_selectedContact !is null)
		{
			// clear all data of this contact
			foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
				el.onHide();
			m_selectedContactData.clear();
			m_selectedContactDataByTime.clear();
		}
		if (rhs !is null)
		{
			// generate data elements from data of this contact
			foreach (ClientContactData* ctd; rhs.contact.contactDataRange)
				addSelectedContactData(ctd);
		}
		m_selectedContact = rhs;
	}

	/// Completely new contact data must be rendered for selectedContact
	void addSelectedContactData(ClientContactData* ctd)
	{
		ContactDataOverlayElement newElement;
		switch (ctd.type)
		{
			case (DataType.Position):
				newElement = new PositionDataTacticalElement(this, ctd);
				break;
			case (DataType.Ray):
				newElement = new RayDataTacticalElement(this, ctd);
				break;
			default:
				return;
		}
		m_selectedContactData[ctd.id] = newElement;
		addOrUpdateCdoeToTree(newElement);
	}

	/// Contact data must no longer be rendered for selectedContact
	void dropSelectedContactData(int id)
	{
		ContactDataOverlayElement* existing = id in m_selectedContactData;
		if (existing)
		{
			existing.onHide();
			m_selectedContactData.remove(id);
			removeCdoeFromTree(*existing);
		}
	}

	override void add(OverlayElement el)
	{
		ContactDataOverlayElement cdoe = cast(ContactDataOverlayElement) el;
		if (cdoe)
		{
			m_selectedContactData[cdoe.data.id] = cdoe;
			addOrUpdateCdoeToTree(cdoe);
			return;
		}
		m_elements[el] = true;
	}

	private void addOrUpdateCdoeToTree(ContactDataOverlayElement cdoe)
	{
		auto equalInTime = m_selectedContactDataByTime.equalRange(cdoe);
		if (equalInTime.empty || equalInTime.filter!(e => e.data.id == cdoe.data.id).empty)
			m_selectedContactDataByTime.stableInsert(cdoe);
	}

	private void removeCdoeFromTree(ContactDataOverlayElement cdoe)
	{
		// we now remove the record from time-sorted tree.
		auto equalInTime = m_selectedContactDataByTime.equalRange(cdoe);
		assert(!equalInTime.empty);
		// Multiple samples can have the same time, we need to reinsert them after removal.
		ContactDataOverlayElement[] toReinsert = equalInTime.filter!(e => e.data.id != cdoe.data.id).array;
		m_selectedContactDataByTime.remove(equalInTime);
		if (toReinsert.length > 0)
			m_selectedContactDataByTime.stableInsert(toReinsert);
	}

	override void remove(OverlayElement el)
	{
		ContactDataOverlayElement cdoe = cast(ContactDataOverlayElement) el;
		if (cdoe)
		{
			m_selectedContactData.remove(cdoe.data.id);
			removeCdoeFromTree(cdoe);
			if (!cdoe.hidden)
				cdoe.onHide();
			return;
		}
		if (selectedContact is el)
			selectedContact = null;
		super.remove(el);
	}

	override void onHide()
	{
		super.onHide();
		foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
		{
			if (!el.hidden)
				el.onHide();
		}
		if (inMerge)
			cancelMerge();
	}

	override void draw(Window wnd, long usecsDelta)
	{
		if (hidden)
			return;
		super.draw(wnd, usecsDelta);
		m_mapGrid.rebuild(this);
		m_mapGrid.draw(wnd);
		foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
		{
			if (!el.hidden)
			{
				el.onPreDraw();
				el.draw(wnd, usecsDelta);
			}
		}
		if (m_hoverDesc.followedContact)
		{
			m_hoverDesc.update();
			m_hoverDesc.mainDiv.draw(wnd, usecsDelta);
		}
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (hidden)
			return null;
		if (rectContainsPoint(x, y))
		{
			foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
			{
				if (!el.hidden && !el.mouseTransparent)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			foreach (OverlayElement el; m_elements.byKey)
			{
				if (!el.hidden && !el.mouseTransparent)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			return this;
		}
		return null;
	}
}


// WARNING: does not support camera rotation.
final class MapGrid
{
	private
	{
		LineShape[] m_horLines;
		LineShape[] m_verLines;
		vec2d m_origin = vec2d(0.0, 0.0);
		double m_interval = 2500.0;
		sfColor m_color;
		float m_width;
	}

	this(sfColor color, float width)
	{
		m_color = color;
		m_width = width;
	}

	void rebuild(Overlay overlay)
	{
		vec2d overlaySize = vec2d(overlay.size.x, overlay.size.y);
		vec2d worldSize = overlay.screen2worldLength(1.0f) * overlaySize;
		vec2d worldLL = overlay.screen2worldPos(vec2d(0.0, overlay.size.y));

		long istart;
		long iend;
		// vertical lines
		getLineIndeces(worldLL.x, worldSize.x, istart, iend);
		assert(iend >= istart - 1);
		assert(abs(iend - istart) < 10000);
		m_verLines.length = (iend - istart + 1).to!size_t;
		foreach (i, ref line; m_verLines)
		{
			double x = istart * m_interval;
			vec2d p1 = overlay.world2screenPos(vec2d(x, worldLL.y));
			vec2d p2 = overlay.world2screenPos(vec2d(x, worldLL.y + worldSize.y));
			if (line is null)
				line = new LineShape(p1, p2, m_color, m_width, true);
			else
				line.setPoints(p1, p2, true);
			istart++;
		}
		// horizontal lines
		getLineIndeces(worldLL.y, worldSize.y, istart, iend);
		assert(iend >= istart - 1);
		assert(abs(iend - istart) < 10000);
		m_horLines.length = (iend - istart + 1).to!size_t;
		foreach (i, ref line; m_horLines)
		{
			double y = istart * m_interval;
			vec2d p1 = overlay.world2screenPos(vec2d(worldLL.x, y));
			vec2d p2 = overlay.world2screenPos(vec2d(worldLL.x + worldSize.x, y));
			if (line is null)
				line = new LineShape(p1, p2, m_color, m_width, true);
			else
				line.setPoints(p1, p2, true);
			istart++;
		}
	}

	private void getLineIndeces(double worldStart, double worldLength,
		out long lineIndexStart, out long lineIndexEnd)
	{
		assert(worldLength >= 0.0);
		lineIndexStart = ceil(worldStart / m_interval).to!long;
		lineIndexEnd = floor((worldStart + worldLength) / m_interval).to!long;
	}

	void draw(Window wnd)
	{
		foreach (line; m_verLines)
			line.render(wnd);
		foreach (line; m_horLines)
			line.render(wnd);
	}
}


final class PingWaveCircleShape: OverlayElement
{
	private
	{
		CircleShape m_shape;
		int m_sonarIdx;
		KinematicSnapshot m_pingStartSnap;
		int m_maxDurationSecs;
	}

	this(TacticalOverlay to, int sonarIdx, int maxDurationSecs,
		KinematicSnapshot pingSnap)
	{
		super(to);
		m_sonarIdx = sonarIdx;
		m_pingStartSnap = pingSnap;
		m_maxDurationSecs = maxDurationSecs;
		mouseTransparent = true;
		m_shape = new CircleShape(0.0f, 90, COLORS.pingWaveCircle, 2);
	}

	@property int sonarIdx() const { return m_sonarIdx; }

	@property bool finished() const
	{
		return m_maxDurationSecs <=
			(Game.simState.lastServerTime - m_pingStartSnap.atTime) / 1000_000L;
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2screenPos(m_pingStartSnap.position);
		m_shape.center = cast(vec2f) screenPos;
		usecs_t estTime = Game.simState.extrapolatedServerTime - m_pingStartSnap.atTime;
		double radius = SonarDisplay.SOUND_SPD / 2.0 * estTime / 1000_000.0;
		m_shape.radius = cast(float) owner.world2screenLength(radius);
		size = (2 * vec2f(m_shape.radius, m_shape.radius)).to!vec2i;
		position = center2lu(screenPos);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_shape.render(wnd);
	}
}


final class ScenarioCircleShape: OverlayElement
{
	private
	{
		CircleShape m_shape;
		MapCircle m_circle;
	}

	this(TacticalOverlay to, const MapElement circleEl)
	{
		assert(circleEl.type == MapElementType.circle);
		super(to);
		mouseTransparent = true;
		m_circle = circleEl.value.circle;
		m_shape = new CircleShape(10.0f, 90, cast(sfColor) circleEl.color,
			m_circle.borderWidth);
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2screenPos(m_circle.center);
		m_shape.center = cast(vec2f) screenPos;
		m_shape.radius = cast(float) owner.world2screenLength(m_circle.radius);
		size = (2 * vec2f(m_shape.radius, m_shape.radius)).to!vec2i;
		position = center2lu(screenPos);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_shape.render(wnd);
	}
}


final class ScenarioTextShape: OverlayElement
{
	private
	{
		TextBox m_box;
		MapText m_text;
	}

	this(TacticalOverlay to, const MapElement textEl)
	{
		assert(textEl.type == MapElementType.text);
		super(to);
		mouseTransparent = true;
		m_text = textEl.value.text;
		m_box = builder(new TextBox()).content(textEl.textContent).
			fontSize(m_text.fontSize).fontColor(cast(sfColor) textEl.color).
			size(vec2i(5000, 5000)).enableScissorTest(false).build;
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2screenPos(m_text.center);
		m_box.position = screenPos.to!vec2i;
		size = vec2i(5, 5);
		position = center2lu(screenPos);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_box.draw(wnd, usecsDelta);
	}
}


/// Icon and velocity vector above the player submarine
final class PlayerSubIcon: OverlayElement
{
	private
	{
		CircleShape m_shape;
		LineShape m_velLine;
		Submarine m_sub;
		enum sfColor BASE_COLOR = sfColor(51, 204, 255, 230);
		TacticalOverlay m_to;
	}

	this(TacticalOverlay to, Submarine sub)
	{
		assert(sub);
		super(to);
		m_to = to;
		m_sub = sub;
		size = vec2i(10, 10);
		m_shape = new CircleShape(5.0f, 12);
		m_shape.borderWidth = 2.0f;
		m_shape.borderColor = BASE_COLOR;
		m_velLine = new LineShape(vec2d(5.0f, 5.0f), vec2d(6.0f, 5.0f), BASE_COLOR, 2.0f);
	}

	private static sfColor getColorFromZoom(double zoom)
	{
		if (zoom >= 2.0)
			return sfTransparent;
		else if (zoom < 0.5)
			return BASE_COLOR;
		sfColor res = BASE_COLOR;
		res.a = (res.a * (1.0 - (zoom - 0.5) / 1.5)).to!ubyte;
		return res;
	}

	override void onPreDraw()
	{
		vec2d screenPos = m_to.world2screenPos(m_sub.transform.position);
		m_shape.center = cast(vec2f) screenPos;
		m_velLine.transform.position = vec2d(screenPos.x, -screenPos.y);
		position = center2lu(screenPos);
		KinematicSnapshot snap;
		if (m_sub.getInterpolatedSnapshot(snap))
		{
			vec2d prograde = snap.velocity;
			if (prograde == vec2d(0.0, 0.0))
				prograde = 1e-3 * courseVector(snap.rotation);
			double velRot = m_to.world2screenRot(courseAngle(prograde));
			double velLen = 5.0 + snap.velocity.length;
			// LineShape is horizontal when transform rotation is zero, so we need
			// to add PI_2 in order to match it with dsubs rotation frame
			m_velLine.transform.rotation = velRot + PI_2;
			m_velLine.transform.scale = vec2d(velLen, 2.0f);
		}
		sfColor color = getColorFromZoom(m_to.m_camCtrl.camera.zoom);
		m_shape.borderColor = color;
		m_velLine.color = color;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_shape.render(wnd);
		m_velLine.render(wnd);
	}
}


/// Contact's icon on F1 screen
final class TacticalContactElement: OverlayElementWithHover
{
	this(TacticalOverlay to, ClientContact contact)
	{
		m_contact = contact;
		m_solution = contact.solution;
		super(to);
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		m_velCircle = ctcOverlayCache.velCircle;
		m_velDragLine = ctcOverlayCache.velDragLine;
		m_pastTrailLine = ctcOverlayCache.pastTrailLine;
		m_rayTracker = ctcOverlayCache.rayTracker;
		m_velLine = new LineShape(vec2d(5.0f, 5.0f), vec2d(6.0f, 5.0f), sfWhite, 2.0f);
		m_descLabel = builder(new Label()).
			fontSize(13).fontColor(sfColor(255, 255, 255, 150)).enableScissorTest(false).
			htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			mouseTransparent(true).build();
		updateFromContact();
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseDown += &processMouseDown;
		onMouseEnter += &processMouseEnter;
		onMouseLeave += &processMouseLeave;

		if (g_velLabel is null)
		{
			g_velLabel = new Label();
			g_velLabel.mouseTransparent = true;
			g_velLabel.fontSize = 12;
			g_velLabel.htextAlign = HTextAlign.LEFT;
			g_velLabel.vtextAlign = VTextAlign.CENTER;
			g_velLabel.size = vec2i(60, 16);
			g_velLabel.enableScissorTest = false;
			g_velLabel.fontColor = sfColor(255, 60, 30, 255);
		}
	}

	void updateFromContact()
	{
		m_mainShape = ctcOverlayCache.forContactType(m_contact.type);
		m_velLine.color = m_mainShape.borderColor;
		m_descLabel.content = m_contact.description;
		m_descLabel.size = cast(vec2i) vec2f(m_descLabel.contentWidth + 10,
				m_descLabel.contentHeight + 2);
		size = cast(vec2i) vec2f(2 * m_mainShape.radius + 8, 2 * m_mainShape.radius + 8);
		// contact id cannot change, so m_contactName is constant
		if (m_contactName is null)
		{
			m_contactName = new Label();
			m_contactName.enableScissorTest = false;
			m_contactName.fontSize = 15;
			m_contactName.content = m_contact.id.to!string;
			m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
				m_contactName.contentHeight + 2);
		}
	}

	private void processMouseEnter(IInputReceiver oldOwner)
	{
		tacowner.m_hoverDesc.followedContact = this;
	}

	private void processMouseLeave(IInputReceiver newOwner)
	{
		TacticalContactElement newEl = cast(TacticalContactElement) newOwner;
		if (newEl is null)
			tacowner.m_hoverDesc.followedContact = null;
	}

	private enum DragMode: ubyte
	{
		main,
		circle,
		trail
	}

	private
	{
		ClientContact m_contact;
		ContactSolution m_solution;
		ContactSolution m_extrapolatedSolution;
		CircleShape m_mainShape, m_velCircle;
		RectangleShape m_onHoverRect;
		LineShape m_velDragLine;
		LineShape m_pastTrailLine;
		LineShape m_velLine;
		LineShape m_rayTracker;
		Label m_contactName;
		Label m_descLabel;
		vec2d m_lastScreenPos;
		DragMode m_dragMode;
		bool m_drawPastTrail;
		bool m_drawRayTracker;
		bool m_rayIntersections = true;
		bool m_drawExtrapolatedPhantom;
		// used in tail dragging
		bool m_draggingWithShift;
		float m_lastRayTrackerBearing;
		vec2d m_lastRayTrackerOrigin;

		enum double RAY_LENGTH = 1000;
	}

	private __gshared Label g_velLabel;

	@property ClientContact contact() { return m_contact; }

	private @property bool needDrawName()
	{
		return m_hovered || (m_contact.type != ContactType.environment &&
			m_contact.type != ContactType.decoy);
	}

	// override @property bool hidden()
	// {
	// 	return !m_contact.solution.posAvailable || super.hidden();
	// }

	@property bool isSelected()
	{
		return tacowner.selectedContact is this;
	}

	/// Overlay elements must ignore mouse scroll in order to not block zooming
	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseWheelScrolled)
			return null;
		// velCircle check
		if (isSelected)
		{
			// check if cursor is inside the circle
			if (pointOnCircle(vec2i(x, y)))
				return this;
			if (pointOnTrail(vec2i(x, y)))
				return this;
		}
		return GuiElement.getFromPoint(evt, x, y);
	}

	private bool pointOnCircle(vec2i point)
	{
		double rad = (m_lastScreenPos - point).length;
		return (rad >= (m_velCircle.radius - 3) &&
				rad <= (m_velCircle.radius + m_velCircle.borderWidth + 3));
	}

	private __gshared double g_trailDragVelPerPixel = 1.0;

	private bool pointOnTrail(vec2i point)
	{
		if (!m_drawPastTrail)
			return false;
		bool inside;
		double k;
		point.y = -point.y;
		vec2d altBase = m_pastTrailLine.getAltitudeBase(cast(vec2d) point, inside, k);
		double altHeight = (altBase - point).length;
		return (inside && altHeight < 7 && (k >= 15 / m_pastTrailLine.length));
	}

	private void extrapolateTime(out usecs_t extrapolatedTime, out double secs)
	{
		extrapolatedTime = Game.simState.extrapolatedServerTime;
		usecs_t usecsSince = extrapolatedTime - m_contact.solution.time;
		secs = usecsSince / 1.0e6;
	}

	private void extrapolatePhantomTime(out usecs_t extrapolatedTime, out double secs)
	{
		extrapolatedTime = Game.simState.extrapolatedServerTime;
		usecs_t usecsSince = extrapolatedTime - m_solution.time;
		secs = usecsSince / 1.0e6;
	}

	@property bool rayTrackingMode() { return m_drawRayTracker; }
	@property float rayTrackerBearing() { return m_lastRayTrackerBearing; }

	override void onPreDraw()
	{
		m_drawRayTracker = false;
		m_drawExtrapolatedPhantom = false;
		if (!isSelected)
		{
			m_solution = m_contact.solution;
			if (!m_solution.posAvailable)
			{
				// ray tracking mode, update m_solution position from ray
				ClientContactData* cd = m_contact.lastRay;
				if (cd !is null)
				{
					m_solution.time = cd.time;
					m_lastRayTrackerBearing = cd.data.ray.bearing;
					m_lastRayTrackerOrigin = cd.data.ray.origin;
					assert(!isNaN(m_lastRayTrackerBearing));
					assert(!isNaN(m_lastRayTrackerOrigin.x));
					assert(!isNaN(m_lastRayTrackerOrigin.y));
					m_solution.pos = m_lastRayTrackerOrigin +
						courseVector(m_lastRayTrackerBearing) * RAY_LENGTH;
					m_drawRayTracker = true;
				}
				else
				{
					// pick deterministic ray bearing based on contact id
					double secsSince;
					extrapolateTime(m_solution.time, secsSince);
					m_solution.pos = Game.simState.playerSub.transform.position +
						courseVector(m_contact.id.postfix + 0.42 * cast(byte) m_contact.id.prefix) * RAY_LENGTH / 2;
				}
			}
			else
			{
				double secsSince;
				extrapolateTime(m_solution.time, secsSince);
				if (m_solution.velAvailable)
					m_solution.pos += secsSince * m_solution.vel;
			}
		}
		else
		{
			if (m_solution.posAvailable && m_solution.velAvailable)
			{
				m_drawExtrapolatedPhantom = true;
				m_extrapolatedSolution = m_solution;
				double secsSince;
				extrapolatePhantomTime(m_extrapolatedSolution.time, secsSince);
				m_extrapolatedSolution.pos += secsSince * m_solution.vel;
			}
		}
		vec2d worldPos = m_solution.pos;
		vec2d screenPos = owner.world2screenPos(worldPos);
		assert(!isNaN(screenPos.x));
		assert(!isNaN(screenPos.y));
		vec2f screenPosF = cast(vec2f) screenPos;
		position = center2lu(screenPos);
		m_mainShape.center = screenPosF;
		if (needDrawName)
		{
			m_contactName.position = vec2i(position.x + size.x / 2 - m_contactName.size.x / 2,
				position.y + size.y - 1);
		}
		m_descLabel.position = vec2i(position.x + size.x / 2 - m_descLabel.size.x / 2,
				position.y + size.y + (needDrawName ? m_contactName.size.y : 0) - 1);
		if (m_hovered)
			m_onHoverRect.center = screenPosF;
		if (m_drawRayTracker)
		{
			m_rayTracker.setPoints(
				owner.world2screenPos(m_lastRayTrackerOrigin), screenPos, true);
		}
		if (isSelected)
		{
			m_velCircle.center = screenPosF;
			if (m_solution.velAvailable)
			{
				// let's update velocity line
				double speed = m_solution.vel.length;
				double vecLen = speed2lineLength(speed);
				m_velCircle.radius = vecLen;
				vec2d velDelta = speed > 1e-20 ?
					m_solution.vel.normalized * vecLen :
					vec2d(0, 0);
				velDelta.y = -velDelta.y;
				vec2d point2 = screenPos + velDelta;
				m_velDragLine.setPoints(screenPos, point2, true);
				g_velLabel.position = cast(vec2i) vec2d(
					point2.x + (velDelta.x >= 0 ? 15 : -70), point2.y);
				g_velLabel.format!"%.2f m/s"(speed);
				// update past trail
				if (speed > 1e-20)
				{
					m_pastTrailLine.setPoints(screenPos,
						screenPos - velDelta.normalized * 1e4, true);
					if (m_hovered)
						m_pastTrailLine.color = sfColor(244, 126, 63, 100);
					else
						m_pastTrailLine.color = sfColor(232, 244, 63, 100);
					m_drawPastTrail = true;
				}
				else
					m_drawPastTrail = false;
			}
			else
				m_velCircle.radius = ZERO_SPD_PIXEL_MARGIN;
		}
		else if (m_solution.velAvailable)
		{
			vec2d velYInv = m_solution.vel;
			velYInv.y = - velYInv.y;
			m_velLine.setPoints(screenPos, screenPos + velYInv, true);
		}
		m_lastScreenPos = screenPos;
	}

	private enum double PIXEL_PER_MPS = 20;
	private enum double ZERO_SPD_PIXEL_MARGIN = 30;
	private enum float DELTA_ALTITUDE = 8;

	private static double lineLength2speed(double len)
	{
		if (len < ZERO_SPD_PIXEL_MARGIN)
			return 0.0;
		return pow((len - ZERO_SPD_PIXEL_MARGIN) / PIXEL_PER_MPS, 2);
	}

	private static double speed2lineLength(double speed)
	{
		return ZERO_SPD_PIXEL_MARGIN + sqrt(speed) * PIXEL_PER_MPS;
	}

	private usecs_t m_lastTriangCheck;
	private vec2d m_lastTriangIntersectRes;

	private enum TriangState
	{
		/// this ray data sample has no triangulation pair
		NOT,
		/// this ray data sample is the first in a triangulation pair
		LEADER,
		/// this ray data sample is the second in a triangulation pair
		FOLLOWER
	}

	/// returns true only if there are two rays intersecting
	private TriangState checkTriangulatingRays(RayDataTacticalElement rel, ref vec2d screenRayIntersection)
	{
		if (rel.data.time == m_lastTriangCheck)
		{
			screenRayIntersection = m_lastTriangIntersectRes;
			return TriangState.FOLLOWER;
		}
		auto timeSlotSamples = tacowner.m_selectedContactDataByTime.equalRange(rel);
		if (timeSlotSamples.save().walkLength < 2)
			return TriangState.NOT;
		ContactDataOverlayElement[] raysInTimeSlot = timeSlotSamples.filter!(cdoe =>
			cast(RayDataTacticalElement) cdoe !is null).array;
		if (raysInTimeSlot.length != 2)
			return TriangState.NOT;
		// now we actually intersect the rays
		RayDataTacticalElement a = cast(RayDataTacticalElement) raysInTimeSlot[0];
		RayDataTacticalElement b = cast(RayDataTacticalElement) raysInTimeSlot[1];
		bool res = a.m_mainShape.intersect(b.m_mainShape, screenRayIntersection);
		if (res)
		{
			m_lastTriangCheck = rel.data.time;
			m_lastTriangIntersectRes = screenRayIntersection;
			return TriangState.LEADER;
		}
		return TriangState.NOT;
	}

	private void drawPastTrailAndDataLines(Window wnd)
	{
		m_pastTrailLine.render(wnd);
		LineShape deltaShape = ctcOverlayCache.dataTrailDelta;
		vec2d deltaPerUsec = -m_solution.vel * tacowner.m_camCtrl.camera.zoom / 1e6;
		deltaPerUsec.y = -deltaPerUsec.y;
		m_lastTriangCheck = 0;
		// iterate all contact data points
		foreach (ContactDataOverlayElement el; tacowner.m_selectedContactDataByTime[])
		{
			vec2d dataPosScreen;
			vec2d dataOnTrail;
			PositionDataTacticalElement pel = cast(PositionDataTacticalElement) el;
			RayDataTacticalElement rel = cast(RayDataTacticalElement) el;
			if (pel !is null)
			{
				dataPosScreen = owner.world2screenPos(
					pel.data.data.position.contactPos);
				dataOnTrail = m_lastScreenPos +
					deltaPerUsec * (m_solution.time - pel.data.time);
				// necessary
				dataPosScreen.y = -dataPosScreen.y;
				dataOnTrail.y = -dataOnTrail.y;
			}
			else
			{
				if (rel !is null)
				{
					dataOnTrail = m_lastScreenPos +
						deltaPerUsec * (m_solution.time - rel.data.time);
					dataOnTrail.y = -dataOnTrail.y;
					TriangState triangState;
					if (m_rayIntersections)
					{
						triangState = checkTriangulatingRays(rel, dataPosScreen);
						if (triangState == TriangState.FOLLOWER)
							continue;
					}
					if (!m_rayIntersections || triangState == TriangState.NOT)
					{
						bool inside;
						double k;
						dataPosScreen = rel.m_mainShape.getAltitudeBase(
							dataOnTrail, inside, k);
					}
				}
				else
					continue;
			}
			// it looks shit if delta line is close to parallel with any of the lines,
			// so we'll always draw two lines. Let's call it an 'error leg'.
			vec2d deltaVec = dataOnTrail - dataPosScreen;
			if (deltaVec.squaredLength < 1e-2)
				continue;	// do not draw delta
			vec2d deltaNorm = deltaVec.normalized;
			vec2d deltaAlt = vec2d(deltaNorm.y, -deltaNorm.x);
			if (el.data.id % 2 == 0)
				deltaAlt = -deltaAlt;
			vec2d deltaMiddlePos = dataPosScreen + 0.5 * deltaVec +
				deltaAlt * DELTA_ALTITUDE;
			deltaShape.setPoints(dataPosScreen, deltaMiddlePos, false);
			deltaShape.render(wnd);
			deltaShape.setPoints(deltaMiddlePos, dataOnTrail, false);
			deltaShape.render(wnd);
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_drawRayTracker)
			m_rayTracker.render(wnd);
		if (isSelected)
		{
			if (m_solution.velAvailable)
			{
				if (m_drawPastTrail)
					drawPastTrailAndDataLines(wnd);
				m_velDragLine.render(wnd);
			}
			if (m_drawExtrapolatedPhantom)
			{
				sfColor savedShapeColor = m_mainShape.borderColor;
				sfColor phantomColor = savedShapeColor;
				phantomColor.a = max(10, savedShapeColor.a - 150).to!ubyte;
				vec2f screenPosF = cast(vec2f) owner.world2screenPos(
					m_extrapolatedSolution.pos);
				vec2f savedCenter = m_mainShape.center;
				m_mainShape.center = screenPosF;
				m_mainShape.borderColor = phantomColor;
				m_mainShape.render(wnd);
				m_mainShape.borderColor = savedShapeColor;
				m_mainShape.center = savedCenter;
			}
			if (!m_dragging)
			{
				if (m_hovered)
					m_velCircle.borderColor = sfColor(255, 0, 0, 150);
				else
					m_velCircle.borderColor = sfColor(255, 255, 255, 150);
				m_velCircle.render(wnd);
			}
		}
		else if (m_solution.velAvailable)
			m_velLine.render(wnd);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		if (isSelected && m_solution.velAvailable)
			g_velLabel.draw(wnd, usecsDelta);
		m_mainShape.render(wnd);
		m_descLabel.draw(wnd, usecsDelta);
		if (needDrawName)
			m_contactName.draw(wnd, usecsDelta);
	}

	@property TacticalOverlay tacowner() { return cast(TacticalOverlay) owner; }

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			if (m_dragging)
			{
				m_dragging = false;
				m_draggingWithShift = false;
				m_dragMode = DragMode.main;
				if (!m_panning)
					returnMouseFocus();
				requestSolutionUpdate();
			}
			if (!m_panning)
			{
				if (tacowner.inMerge)
				{
					if (tacowner.mergeSourceId != m_contact.id)
						Game.ciccon.sendMessage(immutable CICContactMergeReq(
							tacowner.mergeSourceId, m_contact.id));
					tacowner.cancelMerge();
				}
				else
					tacowner.selectedContact = this;
			}
		}
		if (btn == sfMouseRight && !m_panning)
		{
			if (tacowner.inMerge)
				tacowner.cancelMerge();
			Button[] buttons = commonContactContextMenu(m_contact);
			// add merge to button
			Button mbtn = builder(new Button()).fontSize(15).content("merge").build();
			mbtn.onClick += {
				tacowner.startMerge(this, m_contact.id);
			};
			// add toggle triangulation mode
			Button tbtn = builder(new Button()).fontSize(15).content("toggle ray intersect").build();
			tbtn.onClick += {
				m_rayIntersections = !m_rayIntersections;
			};
			buttons ~= mbtn;
			buttons ~= tbtn;
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			final switch (m_dragMode)
			{
				case (DragMode.circle):
				{
					// velocity dragging
					vec2d center = m_lastScreenPos;
					vec2d delta = vec2d(x, y) - center;
					delta.y = -delta.y;	// screen-space y
					double lineLen = delta.length;
					double speed = lineLength2speed(lineLen);
					m_solution.velAvailable = true;
					if (speed >= 1e-20)
						m_solution.vel = speed * delta.normalized;
					else
						m_solution.vel = vec2d(0, 0);
					break;
				}
				case (DragMode.main):
				{
					vec2i newPos = vec2i(x, y) - g_dragOffset;
					vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
					// we now need to update bearing and range from screen-space position
					vec2d newWorldCoord = owner.screen2worldPos(newCenter);
					m_solution.posAvailable = true;
					m_solution.pos = newWorldCoord;
					break;
				}
				case (DragMode.trail):
				{
					// if shift is pressed, we translate instead of velocity
					// modification
					Modifier kbModifiers = HotkeyManager.getCurMod();
					if (kbModifiers & Modifier.SHIFT)
					{
						if (!m_draggingWithShift)
						{
							m_draggingWithShift = true;
							g_dragOffset = vec2i(x, y) - position;
						}
						else
						{
							// repeat DragMode.main logic
							vec2i newPos = vec2i(x, y) - g_dragOffset;
							vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
							vec2d newWorldCoord = owner.screen2worldPos(newCenter);
							m_solution.posAvailable = true;
							m_solution.pos = newWorldCoord;
						}
					}
					else
					{
						m_draggingWithShift = false;
						vec2i newPos = vec2i(x, y);
						vec2d newDelta = m_lastScreenPos - newPos;
						vec2d newVel = newDelta * g_trailDragVelPerPixel /
							tacowner.m_camCtrl.camera.zoom;
						newVel.y = - newVel.y;
						m_solution.vel = newVel;
					}
					break;
				}
			}
		}
	}

	/// Send updated solution to CIC
	private void requestSolutionUpdate()
	{
		Contact contactBody = contact.m_ctc;
		Game.ciccon.sendMessage(
			immutable CICContactUpdateSolutionReq(
				contactBody.id, m_solution, Game.simState.lastServerTime));
	}

	override void drop()
	{
		if (tacowner.inMerge && m_contact.id == tacowner.mergeSourceId)
			tacowner.cancelMerge();
		super.drop();
	}

	void addData(ClientContactData* cdata)
	{
		if (isSelected)
			tacowner.addSelectedContactData(cdata);
	}

	void removeData(int id)
	{
		if (isSelected)
			tacowner.dropSelectedContactData(id);
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && isSelected)
		{
			m_dragging = true;
			if (pointOnCircle(vec2i(x, y)))
				m_dragMode = DragMode.circle;
			else if (pointOnTrail(vec2i(x, y)))
			{
				m_dragMode = DragMode.trail;
				double speed = m_solution.vel.length;
				double vecScreenLen = (m_lastScreenPos - vec2f(x, y)).length;
				assert(vecScreenLen > 1e-20);
				g_trailDragVelPerPixel = speed / vecScreenLen *
					tacowner.m_camCtrl.camera.zoom;
			}
			else
			{
				m_dragMode = DragMode.main;
				g_dragOffset = vec2i(x, y) - position;
			}
			requestMouseFocus();
		}
	}
}


class DataTacticalElement: ContactDataOverlayElement
{
	this(Overlay owner, ClientContactData* data)
	{
		super(owner, data);
		onMouseUp += &processMouseUp;
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = dataContextMenuOptions();
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
	}

	protected Button[] dataContextMenuOptions()
	{
		Button[] res;
		Button btn = builder(new Button()).fontSize(15).content("drop data sample").build();
		btn.onClick += {
			Game.ciccon.sendMessage(immutable CICDropDataReq(data.id));
		};
		res ~= btn;
		return res;
	}
}


/// Waterfall ray sample element.
final class WaterfallRaySampleElement: DataTacticalElement
{
	this(Waterfall.WaterfallOverlay owner, ClientContactData* data)
	{
		assert(data.type == DataType.Ray);
		super(owner, data);
		m_bearing = data.data.ray.bearing;
		m_time = data.time;
		commonInitialization();
	}

	private void commonInitialization()
	{
		m_mainShape = ctcOverlayCache.wfRayDataMainShape;
		m_onHoverRect = ctcOverlayCache.wfRayDataOnHoverRect;
		m_chainLine = ctcOverlayCache.rayChainLine;
		size = cast(vec2i) (m_onHoverRect.size);
		m_contactName = new Label();
		m_contactName.enableScissorTest = false;
		m_contactName.fontSize = 14;
		m_contactName.content = data.ctcId.to!string;
		m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
			m_contactName.contentHeight + 2);
		onMouseUp += &processMouseUp;
		onMouseDown += &processMouseDown;
		onMouseMove += &processMouseMove;
	}

	/// Clone constructor for drag-and-create flow
	this(WaterfallRaySampleElement cloneFrom)
	{
		m_cloneMode = true;
		ContactData dataCopy = cloneFrom.data.cdata;
		// -1 means CIC will allocate new ID for data when sent
		dataCopy.id = -1;
		ClientContactData* fakeData = new ClientContactData(dataCopy);
		super(cloneFrom.owner, fakeData);
		m_next = cloneFrom;
		m_bearing = cloneFrom.m_bearing;
		m_time = cloneFrom.m_time;
		commonInitialization();
		onMouseFocusLoss += &cloneHandleMouseFocusLoss;
	}

	private @property Waterfall.WaterfallOverlay owner()
	{
		return cast(Waterfall.WaterfallOverlay) super.owner;
	}

	private
	{
		// mutable copy of ray data fields
		double m_bearing;
		usecs_t m_time;

		/// true when it is a temporary sample element that is dragged around
		bool m_cloneMode;
		RectangleShape m_mainShape;
		RectangleShape m_onHoverRect;
		// line to connect to m_next sample on waterfall screen
		LineShape m_chainLine;
		// label to draw contact name on hover
		Label m_contactName;
		// closest sample in time
		WaterfallRaySampleElement m_next;
	}

	@property WaterfallRaySampleElement next()
	{
		return m_next;
	}

	@property void next(WaterfallRaySampleElement el)
	{
		m_next = el;
	}

	override Button[] dataContextMenuOptions()
	{
		Button[] res = super.dataContextMenuOptions();
		// if there are multiple hydrophones on our sub, we give the option to
		// duplicate the ray sample on all others.
		if (Game.simState.playerSub.tmpl.hydrophones.length > 1)
		{
			Button btn = builder(new Button()).fontSize(15).
				content("dup to waterfalls").build();
			btn.onClick += {
				int originalSersorId = data.cdata.source.sensorIdx;
				ContactData updated = data.cdata;
				updated.id = -1;
				foreach (i, h; Game.simState.playerSub.tmpl.hydrophones)
				{
					if (i != originalSersorId)
					{
						updated.source.sensorIdx = i.to!int;
						Waterfall.WaterfallOverlay overlay =
							Game.simState.gui.waterfalls[i].overlay;
						// will be invalid if out of waterfall's origin buffer
						overlay.getOrigin(updated.time, updated.data.ray.origin);
						Game.ciccon.sendMessage(immutable CICContactDataReq(updated));
					}
				}
			};
		res ~= btn;
		}
		res ~= classifyAndDescribeContextButtons(contact);
		return res;
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			g_dragOffset = vec2i(x, y) - position;
			// If shift is pressed, we enter new ray data sample creation mode.
			// We create a ray phantom that the user can drag and when released, new
			// ray sample will be sent to CIC.
			Modifier kbModifiers = HotkeyManager.getCurMod();
			if (kbModifiers & Modifier.SHIFT)
			{
				WaterfallRaySampleElement clone = new WaterfallRaySampleElement(this);
				clone.m_dragging = true;
				clone.requestMouseFocus();
				return;
			}
			m_dragging = true;
			requestMouseFocus();
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - g_dragOffset;
			vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
			// we only update bearing for waterfall ray data
			// because waterfall moves down every second and it's inconvenient
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);
			m_bearing = newWorldCoord.x;
			if (m_cloneMode)
			{
				m_time = Game.simState.lastServerTime -
					1000_000L * newWorldCoord.y.to!usecs_t;
			}
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && m_dragging)
		{
			m_dragging = false;
			if (!m_panning)
				returnMouseFocus();
			requestDataUpdate();
		}
	}

	private void cloneHandleMouseFocusLoss()
	{
		this.drop();
	}

	private void requestDataUpdate()
	{
		ContactData updated = data.cdata;
		updated.data.ray.bearing = m_bearing;
		updated.time = m_time;
		bool timeChanged = m_time != data.cdata.time;
		// clone mode simple protection against duplicate samples
		if (!m_cloneMode || timeChanged)
		{
			if (timeChanged)
			{
				// ray origin must be recalculated.
				// will be invalid if out of waterfall's origin buffer.
				owner.getOrigin(m_time, updated.data.ray.origin);
			}
			Game.ciccon.sendMessage(immutable CICContactDataReq(updated));
		}
		// if this was a clone, we destroy it
		if (m_cloneMode)
			this.drop();
	}

	override void updateFromData()
	{
		returnMouseFocus();
		m_bearing = data.data.ray.bearing;
		m_time = data.time;
	}

	override void onPreDraw()
	{
		double bearing = m_bearing;
		long timeDelta = (Game.simState.lastServerTime - m_time) / 1000_000L;
		vec2d screenPos = owner.world2screenPos(vec2d(bearing, timeDelta));
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (m_hovered)
		{
			m_onHoverRect.center = cast(vec2f) screenPos;
			m_contactName.position = vec2i(
				position.x + size.x / 2 - m_contactName.size.x / 2,
				position.y - m_contactName.size.y - 1);
		}
		if (m_next && !m_next.hidden)
		{
			bearing = m_next.m_bearing;
			timeDelta = (Game.simState.lastServerTime - m_next.m_time) / 1000_000L;
			vec2d screenPosNext = owner.world2screenPos(vec2d(bearing, timeDelta));
			m_chainLine.setPoints(screenPos, screenPosNext, true);
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
		{
			m_onHoverRect.render(wnd);
			m_contactName.draw(wnd, usecsDelta);
		}
		if (m_next && !m_next.hidden)
			m_chainLine.render(wnd);
		m_mainShape.render(wnd);
	}
}


/// Tactical overlay element, bound to positional data.
final class PositionDataTacticalElement: DataTacticalElement
{
	this(TacticalOverlay owner, ClientContactData* data)
	{
		assert(data.type == DataType.Position);
		super(owner, data);
		m_mainShape = ctcOverlayCache.posDataMainShape;
		m_onHoverRect = ctcOverlayCache.posDataOnHoverRect;
		size = cast(vec2i) (m_onHoverRect.size);
	}

	private
	{
		RectangleShape m_mainShape;
		RectangleShape m_onHoverRect;
	}

	override void updateFromData() {}

	override protected Button[] dataContextMenuOptions()
	{
		Button[] res = super.dataContextMenuOptions();
		Button btn = builder(new Button()).fontSize(15).content(
			"pivot here").build();
		btn.onClick += {
			TacticalOverlay to = cast(TacticalOverlay) owner;
			TacticalContactElement ce = to.selectedContact;
			if (ce && ce.contact.id == data.ctcId)
			{
				// we move the solution to this point
				ce.m_solution.posAvailable = true;
				ce.m_solution.pos = data.data.position.contactPos;
				ce.m_solution.time = data.time;
				ce.requestSolutionUpdate();
			}
		};
		res ~= btn;
		return res;
	}

	override void onPreDraw()
	{
		vec2d worldPos = data.data.position.contactPos;
		vec2d screenPos = owner.world2screenPos(worldPos);
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (m_hovered)
			m_onHoverRect.center = cast(vec2f) screenPos;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
	}
}


/// Tactical overlay element, bound to ray data.
final class RayDataTacticalElement: DataTacticalElement
{
	this(TacticalOverlay owner, ClientContactData* data)
	{
		assert(data.type == DataType.Ray);
		super(owner, data);
		m_mainShape = ctcOverlayCache.rayDataLine(data.source.sensorIdx, data.time,
			getZeroFadeTime());
		size = vec2i(0, 0);
		mouseTransparent = true;
		onPreDraw();	/// we rely on m_mainShape being initialized after construction
	}

	private
	{
		LineShape m_mainShape;
	}

	override void updateFromData() {}

	private usecs_t getZeroFadeTime()
	{
		ClientContactData* cd = contact.lastRay;
		if (cd)
			return cd.time;
		else
			return Game.simState.extrapolatedServerTime;
	}

	override void onPreDraw()
	{
		vec2d worldPos = data.data.ray.origin;
		vec2d screenPos = owner.world2screenPos(worldPos);
		m_mainShape.setPoints(screenPos, screenPos -
			1e8 * courseVector(-data.data.ray.bearing), true);
		// smear color fading over frames
		if (Game.render.frameCounter % (60 * 3) == (data.id % 16))
		{
			m_mainShape.color = ctcOverlayCache.dimRayColor(
				data.source.sensorIdx, data.time, getZeroFadeTime());
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_mainShape.render(wnd);
	}
}


final class WeaponProjectionTrace: OverlayElement
{
	enum float INTEGRATION_STEP = 1.0f;
	enum sfColor RTE_COLOR = sfColor(245, 141, 5, 100);
	enum sfColor ACTIVE_COLOR = sfColor(255, 10, 10, 100);

	private
	{
		Tube m_tube;
		LineShape[] m_shapes;
		LineShape m_shortestToSolutionShape;
	}

	@property TacticalOverlay owner() { return cast(TacticalOverlay) super.owner; }

	this(TacticalOverlay o, Tube tube)
	{
		super(o);
		m_tube = tube;
		m_shortestToSolutionShape = ctcOverlayCache.shortestToSolution;
		this.mouseTransparent = true;
	}

	override void onPreDraw()
	{
		generateShapes();
	}

	override void draw(Window wnd, long usecsDelta)
	{
		foreach (LineShape shape; m_shapes)
			shape.render(wnd);
		if (owner.selectedContact && owner.selectedContact.contact.solution.posAvailable)
			m_shortestToSolutionShape.render(wnd);
	}

	private static float fuelSpent(float throttle, float fuelExponent)
	{
		return pow(throttle, fuelExponent);
	}

	private void generateShapes()
	{
		float fuel = m_tube.currentWeaponTemplate.fuel;
		float fuelExponent = m_tube.currentWeaponTemplate.fuelExponent;
		float fullThrottleSpd = m_tube.currentWeaponTemplate.fullThrottleSpd;
		float turningRadius = m_tube.currentWeaponTemplate.turningRadius;
		Transform2D trans = new Transform2D();
		trans.position = m_tube.transform.wposition;
		trans.rotation = m_tube.transform.wrotation;
		auto param = WeaponParamType.marchCourse in m_tube.weaponParams;
		float course = clampAngle(param ? param.course : trans.rotation);
		float travelled = 0.0f;
		float speed = m_tube.weaponParams[WeaponParamType.marchSpeed].speed;
		float activationRange = m_tube.weaponParams[WeaponParamType.activationRange].range;
		WeaponSearchPattern pattern = m_tube.weaponParams[WeaponParamType.searchPattern].
			searchPattern;
		// snake-related
		float snakeAngle = dgr2rad(45.0f);
		float snakeArm = m_tube.searchPatternDesc.snakeWidth / cos(snakeAngle);
		float snakeSign = 1.0f;
		// spiral-related

		// contact-related
		TacticalContactElement ctcEl = owner.selectedContact;
		float minDist = float.max;
		vec2d extrapolatedCtPosMin;
		vec2d point2AtMinDist;

		bool activated = false;
		// integrate
		size_t shapeIdx = 0;
		while (fuel > 0.0f)
		{
			if (shapeIdx >= m_shapes.length)
				m_shapes ~= ctcOverlayCache.weaponProjectionLine;
			LineShape shape = m_shapes[shapeIdx];
			vec2d point1 = trans.wposition;
			vec2d point2;
			// consume fuel
			fuel -= INTEGRATION_STEP * fuelSpent(speed / fullThrottleSpd, fuelExponent);
			assert(!isNaN(fuel));
			// find point2
			float desiredCourse = course;
			if (activated)
			{
				shape.color = ACTIVE_COLOR;
				// process search patterns
				final switch (pattern)
				{
					case WeaponSearchPattern.straight:
						break;
					case WeaponSearchPattern.snake:
					{
						float sinceActivation = travelled - activationRange;
						float shiftedToArm = sinceActivation + snakeArm * 0.5f;
						int divRes = ceil(shiftedToArm / snakeArm).to!int;
						if (divRes % 2 == 0)
							snakeSign = -1.0f;
						else
							snakeSign = 1.0f;
						desiredCourse = course + snakeAngle * snakeSign;
						break;
					}
					case WeaponSearchPattern.spiral:
					{
						float sinceActivation = travelled - activationRange;
						desiredCourse = trans.wrotation + (INTEGRATION_STEP * speed) /
							(m_tube.searchPatternDesc.spiralFirstRadius * (1.0f +
							sqrt(sinceActivation / 1.5f / PI /
								m_tube.searchPatternDesc.spiralStep)));
						break;
					}
				}
			}
			else
				shape.color = RTE_COLOR;
			double courseDist = angleDist(desiredCourse, trans.wrotation);
			if (courseDist == 0.0)
			{
				// straight line
				point2 = point1 + trans.wforward * speed * INTEGRATION_STEP;
			}
			else
			{
				// full or partial turn
				float maxCourseDistPerInterval = speed * INTEGRATION_STEP / turningRadius;
				trans.rotation = trans.rotation + max(-maxCourseDistPerInterval,
					min(maxCourseDistPerInterval, courseDist));
				point2 = point1 + trans.wforward * speed * INTEGRATION_STEP;
			}
			trans.position = point2;
			shape.setPoints(
				owner.world2screenPos(point1),
				owner.world2screenPos(point2),
				true);
			travelled += speed * INTEGRATION_STEP;
			if (!activated && travelled >= activationRange)
			{
				activated = true;
				speed = m_tube.weaponParams[WeaponParamType.activeSpeed].speed;
			}
			// contact-related stuff
			if (ctcEl && ctcEl.contact.solution.posAvailable)
			{
				vec2d extrapolatedCtPos = ctcEl.contact.solution.pos;
				if (ctcEl.contact.solution.velAvailable)
				{
					usecs_t extrapolatedTime = Game.simState.extrapolatedServerTime;
					usecs_t usecsSince = extrapolatedTime - ctcEl.contact.solution.time;
					float secs = usecsSince / 1.0e6f;
					extrapolatedCtPos += (shapeIdx * INTEGRATION_STEP + secs) * ctcEl.contact.solution.vel;
				}
				float sqrDistance = (extrapolatedCtPos - point2).squaredLength;
				if (sqrDistance < minDist)
				{
					extrapolatedCtPosMin = extrapolatedCtPos;
					minDist = sqrDistance;
					point2AtMinDist = point2;
				}
			}

			shapeIdx++;
		}
		m_shapes = m_shapes[0..shapeIdx];

		if (ctcEl && ctcEl.contact.solution.posAvailable)
		{
			m_shortestToSolutionShape.setPoints(
				owner.world2screenPos(point2AtMinDist),
				owner.world2screenPos(extrapolatedCtPosMin),
				true);
		}
	}
}


/// Draggable element that can be used to edit march course and
/// activation range of a weapon.
final class WeaponAimHandle: OverlayElementWithHover
{
	private
	{
		Tube m_tube;
		TubeUI m_tubeUi;
		CircleShape m_circleShape;
		Label m_tubeNumberLabel;
	}

	this(TacticalOverlay to, Tube tube, TubeUI tui)
	{
		super(to);
		m_tube = tube;
		m_tubeUi = tui;
		m_circleShape = ctcOverlayCache.tubeCircle;
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		m_tubeNumberLabel = builder(new Label()).mouseTransparent(true).
			enableScissorTest(false).fontSize(18).
			htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			fontColor(COLORS.tubeCircle).content((tube.id + 1).to!string).build();
		int boxSize = (m_circleShape.radius + m_circleShape.borderWidth).to!int;
		m_tubeNumberLabel.size = this.size = vec2i(2 * boxSize, 2 * boxSize);
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_circleShape.render(wnd);
		m_tubeNumberLabel.draw(wnd, usecsDelta);
	}

	override void onPreDraw()
	{
		Transform2D tubeTrans = m_tube.transform;
		auto param = WeaponParamType.marchCourse in m_tube.weaponParams;
		float course = clampAngle(param ? param.course : tubeTrans.wrotation);
		float activationRange = m_tube.weaponParams[WeaponParamType.activationRange].range;

		vec2d worldCenter = tubeTrans.wposition + courseVector(course) * activationRange;
		vec2d screenCenter = owner.world2screenPos(worldCenter);
		vec2f screenCenterf = cast(vec2f) screenCenter;
		m_circleShape.center = screenCenterf;
		position = center2lu(screenCenter);
		m_tubeNumberLabel.position = position;
		if (m_hovered)
		{
			m_onHoverRect.center = screenCenterf;
			m_onHoverRect.size = cast(vec2f) size;
		}
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			m_dragging = true;
			g_dragOffset = vec2i(x, y) - position;
			requestMouseFocus();
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && m_dragging)
		{
			m_dragging = false;
			if (!m_panning)
				returnMouseFocus();
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - g_dragOffset;
			vec2d newCenter = owner.clampInsideRect(newPos);
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);

			Transform2D tubeTrans = m_tube.transform;
			vec2d delta = newWorldCoord - tubeTrans.wposition;
			float clampedActivRange = m_tube.activationRangeLimits.clamp(delta.length);
			float course = courseAngle(delta);
			m_tube.activationRange = clampedActivRange;
			m_tube.marchCourse = course;
			m_tube.activeCourse = course;
			m_tubeUi.updateAimFieldsFromTube();
		}
	}
}


final class HoveredContactDescription
{
	private
	{
		Div m_mainDiv;
		Label[] m_labels;
		TacticalContactElement m_followedContact;
		int m_counter = UPDATE_FREQ - 1;

		enum int UPDATE_FREQ = 20;
		enum int DIV_WIDTH = 150;
	}

	@property TacticalContactElement followedContact() { return m_followedContact; }

	@property void followedContact(TacticalContactElement rhs)
	{
		m_followedContact = rhs;
		m_counter = UPDATE_FREQ - 1;
	}

	@property Div mainDiv() { return m_mainDiv; }

	this()
	{
		m_labels = new Label[9];
		for (int i = 0; i < m_labels.length; i++)
		{
			Label lbl = new Label();
			lbl.mouseTransparent = true;
			lbl.fontSize = 14;
			lbl.htextAlign = HTextAlign.LEFT;
			m_labels[i] = lbl;
		}
		m_mainDiv = new Div(DivType.VERT, cast(GuiElement[]) m_labels);
		m_mainDiv.backgroundVisible = true;
		m_mainDiv.backgroundColor = COLORS.simOverlayDivBgnd;
		m_mainDiv.mouseTransparent = true;
		m_mainDiv.size = vec2i(DIV_WIDTH, (m_labels.length * 20).to!int);
	}

	void update()
	{
		if (m_followedContact is null)
			return;
		m_counter = (m_counter + 1) % UPDATE_FREQ;
		if (m_counter != 0)
			return;
		m_labels[0].format!"id: %s"(m_followedContact.contact.id);
		m_labels[1].format!"desc: %s"(m_followedContact.contact.description);
		m_labels[2].format!"type: %s"(m_followedContact.contact.type);
		m_labels[3].format!"age: %ss"(
			(Game.simState.lastServerTime - m_followedContact.contact.createdAt).
			dur!"usecs".total!"seconds");
		m_labels[4].format!"updated: %ss"(
			(Game.simState.lastServerTime - m_followedContact.contact.solutionUpdatedAt).
			dur!"usecs".total!"seconds");
		if (m_followedContact.m_solution.posAvailable)
		{
			vec2d dirVec = m_followedContact.m_solution.pos -
					Game.simState.playerSub.transform.wposition;
			m_labels[5].format!"bearing: %.1f"(
				-courseAngle(dirVec).compassAngle.rad2dgr);
			m_labels[6].format!"range: %dm"(dirVec.length.to!int);
		}
		else
		{
			if (m_followedContact.rayTrackingMode)
				m_labels[5].format!"bearing: %.1f"(
					-compassAngle(m_followedContact.rayTrackerBearing).rad2dgr);
			else
				m_labels[5].format!"bearing: ?"();
			m_labels[6].format!"range: ?"();
		}
		if (m_followedContact.m_solution.velAvailable)
		{
			vec2d velVec = m_followedContact.m_solution.vel;
			m_labels[7].format!"course: %.1f"(
				-courseAngle(velVec).compassAngle.rad2dgr);
			m_labels[8].format!"speed: %.2fm/s"(velVec.length);
		}
		else
		{
			m_labels[7].format!"course: ?"();
			m_labels[8].format!"speed: ?"();
		}
	}
}