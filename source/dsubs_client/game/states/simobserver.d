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
module dsubs_client.game.states.simobserver;

import std.algorithm: min;
import std.math: floor;
import std.json;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api.messages;
import dsubs_common.api.entities;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.input.hotkeymanager;
import dsubs_client.render.shapes;
import dsubs_client.game;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.cic.messages;
import dsubs_client.game.gamestate;
import dsubs_client.game.tacoverlay;
import dsubs_client.game.states.loginscreen;
import dsubs_client.gui;


private
{
	enum int HEADER_FONT = 22;
	enum int SIMID_FONT = 12;
	enum int EL_DATA_FONT = 12;
}


private struct EntityElementPair
{
	ObservableEntityUpdate record;
	SimObserverEl overlayElement;
	bool stillExistsFlag;
	JSONValue parsedJson;
}


/// Observe and manipulate some running simulator
final class SimObserverState: GameState
{
	private
	{
		string m_simUniqId;
		CameraController m_camController;
		SimObserverOverlay m_overlay;
		EntityElementPair*[string] m_existingEntities;
		ContactOverlayShapeCahe m_shapeCache;
		DevObserveSimulatorRes m_firstFullUpdate;
		ObserverGui m_observerGui;
		string m_selectedElementId;
	}

	@property ObserverGui gui() { return m_observerGui; }

	@property string selectedElementId() const { return m_selectedElementId; }

	@property void selectedElementId(string rhs)
	{
		if (rhs == m_selectedElementId)
			return;
		m_selectedElementId = rhs;
		// set content to json
		EntityElementPair** pair = rhs in m_existingEntities;
		updateSelectedElementText(pair);
	}

	private void updateSelectedElementText(EntityElementPair** pair)
	{
		if (pair)
		{
			dstring newContent = (*pair).parsedJson.toPrettyString().to!dstring;
			m_observerGui.m_selectedElementText.content = newContent;
		}
		else
			m_observerGui.m_selectedElementText.content = ""d;
	}

	this(DevObserveSimulatorRes res)
	{
		assert(res.success);
		m_simUniqId = res.simRecord.uniqId;
		m_firstFullUpdate = res;
		m_shapeCache = new ContactOverlayShapeCahe();
	}

	override void setup()
	{
		trace("got ", m_firstFullUpdate.allEntities.length,
			" entities in the observed simulator: ", m_simUniqId);
		// set up camera
		Game.worldManager.camCtx.camera.center = vec2d(0, 0);
		Game.worldManager.camCtx.camera.zoom = 0.01;
		m_camController = new CameraController(Game.worldManager.camCtx.camera);
		m_overlay = new SimObserverOverlay(m_camController);
		Game.guiManager.addPanel(new Panel(m_overlay));
		m_observerGui = new ObserverGui(m_simUniqId, m_overlay);

		rebuildFromEmpty(m_firstFullUpdate.allEntities);
		m_firstFullUpdate.allEntities.length = 0;
	}

	private void rebuildFromEmpty(ObservableEntityUpdate[] entities)
	{
		m_existingEntities.clear();
		m_overlay.clear();
		foreach (ObservableEntityUpdate record; entities)
		{
			EntityElementPair* pair = new EntityElementPair(record, null);
			pair.parsedJson = parseJSON(record.stateUpdateJson);
			pair.overlayElement = new SimObserverEl(m_overlay, &pair.record,
				&pair.parsedJson);
			m_existingEntities[record.id] = pair;
			m_overlay.add(pair.overlayElement);
		}
	}

	void handleDevObserverSimulatorUpdateRes(DevObserverSimulatorUpdateRes res)
	{
		trace("handleDevObserverSimulatorUpdateRes");
		foreach (EntityElementPair* pair; m_existingEntities.byValue)
			pair.stillExistsFlag = false;
		foreach (ObservableEntityUpdate record; res.existingEntities)
		{
			EntityElementPair** pairPtr = record.id in m_existingEntities;
			if (pairPtr is null)
			{
				// new entity
				EntityElementPair* pair = new EntityElementPair(record, null, true);
				pair.parsedJson = parseJSON(record.stateUpdateJson);
				pair.overlayElement = new SimObserverEl(m_overlay, &pair.record,
					&pair.parsedJson);
				m_existingEntities[record.id] = pair;
				m_overlay.add(pair.overlayElement);
			}
			else
			{
				// existing entity
				EntityElementPair* pair = *pairPtr;
				pair.stillExistsFlag = true;
				pair.record = record;
				pair.parsedJson = parseJSON(record.stateUpdateJson);
				// trace("pair.overlayElement.updateFromRecord(): ", record);
				pair.overlayElement.updateFromRecord();
				if (m_selectedElementId == record.id)
					updateSelectedElementText(pairPtr);
			}
		}
		// build the list of dead entities
		string[] idsToRemove;
		foreach (EntityElementPair* pair; m_existingEntities.byValue)
		{
			if (!pair.stillExistsFlag)
			{
				idsToRemove ~= pair.record.id;
				pair.overlayElement.drop();
				if (pair.record.id == m_selectedElementId)
					selectedElementId = null;
			}
		}
		foreach (string id; idsToRemove)
			m_existingEntities.remove(id);
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}
}


final class ObserverGui
{
	private
	{
		Button m_abandonBtn;
		Div m_mainDiv;
		Div m_headerDiv;
		Div m_middleScreenDiv;
		TextBox m_selectedElementText;
	}

	this(string simulatorId, SimObserverOverlay overlay)
	{
		Label simIdLabel = builder(new Label()).content("simulator_id: " ~ simulatorId).
			fontSize(SIMID_FONT).fixedSize(vec2i(400, 10)).build;

		m_abandonBtn = builder(new Button(ButtonType.ASYNC)).content("X").
				fixedSize(vec2i(HEADER_FONT + 5, HEADER_FONT + 5)).fontSize(HEADER_FONT).
				backgroundColor(COLORS.simLaunchButtonBgnd).build;
		m_abandonBtn.onClick += {
			startYesNoDialog("Confirm stop observing simulator",
				{
					trace("sending request to abort observation");
					Game.bconm.con.sendMessage(immutable DevStopObservingReq());
					// this will switch us to devmenu again
					Game.bconm.con.sendMessage(immutable DevSimulatorsListReq());
				},
				{
					m_abandonBtn.signalClickEnd();
				},
				440);
		};

		m_headerDiv = builder(hDiv([m_abandonBtn, simIdLabel, filler()])).fixedSize(
				vec2i(10, HEADER_FONT + 5)).backgroundColor(COLORS.simPanelBgnd).build;

		// selected element description
		m_selectedElementText = builder(new TextBox()).
			backgroundColor(COLORS.simPanelBgnd).fontSize(EL_DATA_FONT).build;
		ScrollBar selectedElScrollBar = builder(new ScrollBar(m_selectedElementText)).build;
		m_middleScreenDiv = builder(hDiv([filler(0.77f), selectedElScrollBar])).build;

		// Stack tacticalScreenStack = builder(new Stack([
		// 	overlay, m_middleScreenDiv])).fraction(1000.0f).build();

		m_mainDiv = vDiv([
			m_headerDiv,
			m_middleScreenDiv]);
		Game.guiManager.addPanel(new Panel(m_mainDiv));
	}
}


// TODO: deduplicate with OverlayElementWithHover
final class SimObserverEl: OverlayElement
{
	private
	{
		CircleShape m_shape;
		LineShape m_velLine;
		Label m_prototypeLabel;
		Label m_nameLabel;
		ObservableEntityUpdate* m_record;
		JSONValue* m_jsonState;
		RectangleShape m_onHoverRect;
		bool m_hovered;
	}

	this(Overlay owner, ObservableEntityUpdate* record, JSONValue* parsedJson)
	{
		super(owner);
		mouseTransparent = false;
		m_record = record;
		m_jsonState = parsedJson;
		switch (record.entityType)
		{
			case "Submarine":
				m_shape = Game.simObserverState.m_shapeCache.forContactTypeNew(
					ContactType.submarine);
				break;
			default:
				m_shape = Game.simObserverState.m_shapeCache.forContactTypeNew(
					ContactType.unknown);
				break;
		}
		m_velLine = new LineShape(vec2d(5.0f, 5.0f), vec2d(6.0f, 5.0f), m_shape.borderColor, 2.0f);

		m_prototypeLabel = builder(new Label()).fontSize(12).fontColor(sfColor(200, 200, 200, 150)).
			enableScissorTest(false).htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			mouseTransparent(true).build();
		m_nameLabel = builder(new Label()).fontSize(14).fontColor(sfWhite).
			enableScissorTest(false).htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			mouseTransparent(true).build();

		m_prototypeLabel.content = m_record.entityType;
		m_prototypeLabel.size = cast(vec2i) vec2f(m_prototypeLabel.contentWidth + 10,
				m_prototypeLabel.contentHeight + 2);
		m_nameLabel.content = m_record.id;
		m_nameLabel.size = cast(vec2i) vec2f(m_nameLabel.contentWidth + 10,
				m_nameLabel.contentHeight + 2);
		size = cast(vec2i) vec2f(2 * m_shape.radius + 8, 2 * m_shape.radius + 8);

		updateFromRecord();

		m_onHoverRect = Game.simObserverState.m_shapeCache.onHoverRect;
		onMouseEnter += (o) {
			trace("mouse entered");
			m_hovered = true;
		};
		onMouseLeave += (o) { m_hovered = false; };
		onMouseUp += &processMouseUp;
	}

	void updateFromRecord()
	{
		assert(m_jsonState);
		if ((*m_jsonState)["dead"].boolean)
			m_shape.borderColor = sfColor(100, 100, 100, 255);
	}

	override void onPreDraw()
	{
		// TODO: kinematic interpolation
		vec2d worldPos = cast(vec2d) m_record.transformSnapshot.position;
		vec2d screenPos = owner.world2screenPos(worldPos);
		assert(!isNaN(screenPos.x));
		assert(!isNaN(screenPos.y));
		vec2f screenPosF = cast(vec2f) screenPos;
		position = center2lu(screenPos);
		m_shape.center = screenPosF;
		vec2d velYInv = cast(vec2d) m_record.transformSnapshot.velocity;
		velYInv.y = - velYInv.y;
		m_velLine.setPoints(screenPos, screenPos + velYInv, true);
		m_prototypeLabel.position = vec2i(position.x + size.x / 2 - m_prototypeLabel.size.x / 2,
			position.y + size.y - 1);
		m_nameLabel.position = vec2i(position.x + size.x / 2 - m_nameLabel.size.x / 2,
			position.y + size.y + m_prototypeLabel.size.y - 1);
		if (m_hovered)
		{
			m_onHoverRect.center = cast(vec2f) screenPos;
			m_onHoverRect.size = cast(vec2f) size;
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_shape.render(wnd);
		m_velLine.render(wnd);
		m_prototypeLabel.draw(wnd, usecsDelta);
		m_nameLabel.draw(wnd, usecsDelta);
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && !m_panning)
		{
			Game.simObserverState.selectedElementId = m_record.id;
		}
	}
}


final class SimObserverOverlay: WorldSpaceOverlay
{
	this(CameraController camCtrl)
	{
		super(camCtrl);
		mouseTransparent = false;
	}
}