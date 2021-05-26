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
module dsubs_client.game.contacts;

import std.traits: EnumMembers;
import std.container.rbtree: RedBlackTree;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.game.cic.messages;
import dsubs_client.game.sonardisp: SonarDisplay;
import dsubs_client.game.waterfall: Waterfall;
import dsubs_client.game.tacoverlay;
import dsubs_client.game;


/// Client representation of ContactData object
struct ClientContactData
{
	this(ContactData data)
	{
		m_data = data;
	}

	private ContactData m_data;
	@property const(ContactData) cdata() const { return m_data; }
	alias cdata this;
}


/// Client representation of a contact object
final class ClientContact
{
	this(Contact ctc, int hydrophoneCount)
	{
		m_ctc = ctc;
		m_tactDispEl = new TacticalContactElement(Game.simState.tacticalOverlay, this);
		m_trackerEls.length = hydrophoneCount;
	}

	private SonarDispContactDataElement m_sonarDispEl;
	private TacticalContactElement m_tactDispEl;
	private HydrophoneTrackerElement[] m_trackerEls;
	private WaterfallRaySampleElement[int] m_rayWaterfallEls;

	// ordered trees of ray contact datas that is used to build the chain of
	// samples, ordered by sensorIdx
	alias ClientContactDataTree = RedBlackTree!(const(ClientContactData)*,
		"a.time < b.time || (a.time == b.time && a.id < b.id)", false);
	private ClientContactDataTree[int] m_rayWaterfallDataTrees;

	private WaterfallRaySampleElement getNextRayData(const(ClientContactData)* rayData)
	{
		ClientContactDataTree* treePtr =
			rayData.source.sensorIdx in m_rayWaterfallDataTrees;
		if (treePtr is null)
			return null;
		ClientContactDataTree tree = *treePtr;
		auto largerRange = tree.upperBound(rayData);
		if (largerRange.empty)
			return null;
		const(ClientContactData)* next = largerRange.front();
		assert(next.id != rayData.id);
		return m_rayWaterfallEls[next.id];
	}

	private WaterfallRaySampleElement getPrevRayData(const(ClientContactData)* rayData)
	{
		ClientContactDataTree* treePtr =
			rayData.source.sensorIdx in m_rayWaterfallDataTrees;
		if (treePtr is null)
			return null;
		ClientContactDataTree tree = *treePtr;
		auto lessRange = tree.lowerBound(rayData);
		if (lessRange.empty)
			return null;
		const(ClientContactData)* prev = lessRange.back();
		assert(prev.id != rayData.id);
		return m_rayWaterfallEls[prev.id];
	}

	// insert client contact data in the tree and
	// update the linked list of waterfall elements, related to one contact
	private void insertRayDataInTree(WaterfallRaySampleElement wfel)
	{
		WaterfallRaySampleElement prev = getPrevRayData(wfel.data);
		if (prev)
		{
			// most common case: in-order append
			wfel.next = prev.next;
			prev.next = wfel;
		}
		else
		{
			WaterfallRaySampleElement next = getNextRayData(wfel.data);
			wfel.next = next;
		}
		int sensorIdx = wfel.data.source.sensorIdx;
		ClientContactDataTree* treePtr = sensorIdx in m_rayWaterfallDataTrees;
		ClientContactDataTree tree;
		if (treePtr is null)
		{
			tree = new ClientContactDataTree();
			m_rayWaterfallDataTrees[sensorIdx] = tree;
		}
		else
			tree = *treePtr;
		tree.stableInsert(wfel.data);
	}

	private void removeRayDataFromTree(WaterfallRaySampleElement el)
	{
		int sensorIdx = el.data.source.sensorIdx;
		ClientContactDataTree* treePtr = sensorIdx in m_rayWaterfallDataTrees;
		ClientContactDataTree tree = *treePtr;
		assert(treePtr !is null);
		tree.removeKey(el.data);
		// maintain list connectivity
		WaterfallRaySampleElement prevEl = getPrevRayData(el.data);
		if (prevEl)
			prevEl.next = el.next;
	}

	void trimRayTrees(usecs_t before)
	{
		ContactData timeBarrier;
		timeBarrier.time = before;
		ClientContactData timeBarrier2 = ClientContactData(timeBarrier);
		foreach (tree; m_rayWaterfallDataTrees.byValue)
		{
			auto olderDataRange = tree.lowerBound(&timeBarrier2);
			auto savedRange = olderDataRange.save();
			foreach (rayToRemove; olderDataRange)
			{
				m_rayWaterfallEls[rayToRemove.id].drop();
				m_rayWaterfallEls.remove(rayToRemove.id);
			}
			tree.remove(savedRange);
		}
	}

	/// Last added ray. This field is not updated by data point deletion or updates,
	/// only addition.
	mixin Readonly!(ClientContactData*, "lastRay");

	/// collection of all data of this contact
	private ClientContactData*[int] m_dataHash;
	/// get ContactData iterator
	auto contactDataRange() { return m_dataHash.byValue; }

	HydrophoneTrackerElement[] trackerElements() { return m_trackerEls; }

	Contact m_ctc;
	alias m_ctc this;

	void drop()
	{
		m_tactDispEl.drop();
		if (m_sonarDispEl)
		{
			m_sonarDispEl.drop();
			m_sonarDispEl = null;
		}
		foreach (hte; m_trackerEls)
		{
			if (hte !is null)
				hte.drop();
		}
		foreach (wfEl; m_rayWaterfallEls.byValue)
			wfEl.drop();
		m_rayWaterfallEls.clear();
		m_rayWaterfallDataTrees.clear();
		m_dataHash.clear();
	}

	void addData(ClientContactData* cdata)
	{
		m_dataHash[cdata.id] = cdata;
		if (cdata.type == DataType.Ray)
		{
			if (m_lastRay is null)
				m_lastRay = cdata;
			else if (m_lastRay.time <= cdata.time)
				m_lastRay = cdata;
			if (cdata.source.type == DataSourceType.Hydrophone)
			{
				int sensorId = cdata.source.sensorIdx;
				WaterfallRaySampleElement newEl =
					new WaterfallRaySampleElement(
						Game.simState.gui.waterfalls[sensorId].overlay, cdata);
				insertRayDataInTree(newEl);
				m_rayWaterfallEls[cdata.id] = newEl;
			}
		}
		switch (cdata.source.type)
		{
			case DataSourceType.ActiveSonar:
				if (m_sonarDispEl !is null)
				{
					if (m_sonarDispEl.data.time < cdata.time)
					{
						// old m_sonarDispEl must go
						m_sonarDispEl.drop();
						m_sonarDispEl = new SonarDispContactDataElement(
							Game.simState.gui.sonardisp.overlay, cdata, this);
					}
				}
				else
				{
					m_sonarDispEl = new SonarDispContactDataElement(
						Game.simState.gui.sonardisp.overlay, cdata, this);
				}
				break;
			default:
				break;
		}
		m_tactDispEl.addData(cdata);
	}

	void updateContact(MsgT)(MsgT msg)
		if (isContactUpdateMsg!MsgT)
	{
		static if (is(MsgT == CICContactUpdateTypeReq))
			m_ctc.type = msg.type;
		else static if (is(MsgT == CICContactUpdateSolutionReq))
		{
			m_ctc.solution = msg.solution;
			m_ctc.solutionUpdatedAt = msg.solutionUpdatedAt;
		}
		else static if (is(MsgT == CICContactUpdateDescriptionReq))
			m_ctc.description = msg.description;
		else static if (is(MsgT == CICContactUpdateReq))
		{
			m_ctc.type = msg.type;
			m_ctc.solution = msg.solution;
			m_ctc.solutionUpdatedAt = msg.solutionUpdatedAt;
			m_ctc.description = msg.description;
		}
		m_tactDispEl.updateFromContact();
		if (m_sonarDispEl)
			m_sonarDispEl.updateFromContact(this);
	}

	void updateData(ClientContactData* cdata)
	{
		if (m_sonarDispEl && m_sonarDispEl.data is cdata)
			m_sonarDispEl.updateFromData();
		if (cdata.id in m_rayWaterfallEls)
		{
			WaterfallRaySampleElement wfel = m_rayWaterfallEls[cdata.id];
			if (cdata.time != wfel.data.time)
			{
				removeRayDataFromTree(wfel);
				insertRayDataInTree(wfel);
			}
			wfel.updateFromData();
		}
	}

	void updateTracker(HydrophoneTracker ht)
	{
		if (m_trackerEls[ht.id.sensorIdx] is null)
		{
			// new tracker
			Waterfall.TrackerOverlay wto = Game.simState.gui.
				waterfalls[ht.id.sensorIdx].trackerOverlay;
			m_trackerEls[ht.id.sensorIdx] = new HydrophoneTrackerElement(wto, ht);
		}
		else
		{
			// update old one
			m_trackerEls[ht.id.sensorIdx].updateFromTracker(ht);
		}
	}

	void dropTracker(int hydrophoneIdx)
	{
		if (m_trackerEls[hydrophoneIdx])
			m_trackerEls[hydrophoneIdx].drop();
		m_trackerEls[hydrophoneIdx] = null;
	}

	void removeData(int dataId)
	{
		m_dataHash.remove(dataId);
		if (m_sonarDispEl && m_sonarDispEl.data.id == dataId)
		{
			m_sonarDispEl.drop();
			m_sonarDispEl = null;
		}
		m_tactDispEl.removeData(dataId);
		if (dataId in m_rayWaterfallEls)
		{
			WaterfallRaySampleElement el = m_rayWaterfallEls[dataId];
			el.drop();
			m_rayWaterfallEls.remove(dataId);
			removeRayDataFromTree(el);
		}
	}
}


/// Contacts and their data that the client knows about. May be out of sync with CIC server.
final class ClientContactManager
{
	private int m_hydrophoneCount;

	this(CICReconnectStateRes msg, int hydrophoneCount)
	{
		m_hydrophoneCount = hydrophoneCount;
		foreach (Contact ctc; msg.contacts)
			m_contactHash[ctc.id] = new ClientContact(ctc, hydrophoneCount);
	}

	/// collection of all data of this contact
	private ClientContact[ContactId] m_contactHash;
	/// collection of all contact data
	private ClientContactData*[int] m_dataHash;

	ClientContact get(ContactId id) { return m_contactHash[id]; }

	void handleContactCreated(CICContactCreatedFromDataRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null, "contact already exists");
		m_contactHash[msg.newContact.id] = new ClientContact(msg.newContact, m_hydrophoneCount);
		handleContactData(msg.initialData);
	}

	void handleContactCreated(CICContactCreatedFromHTrackerRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null, "contact already exists");
		m_contactHash[msg.newContact.id] = new ClientContact(msg.newContact, m_hydrophoneCount);
		handleTracker(msg.tracker);
	}

	void handleTracker(HydrophoneTracker tracker)
	{
		ContactId cid = tracker.id.ctcId;
		ClientContact cc = m_contactHash[cid];
		cc.updateTracker(tracker);
	}

	void handleContactData(ContactData newData)
	{
		ClientContact* ctc = newData.ctcId in m_contactHash;
		enforce(ctc !is null, "contact does not exist");
		ClientContactData** existing = newData.id in m_dataHash;
		if (existing !is null)
		{
			if (ctc.id != (*existing).ctcId)
			{
				// data changed owner
				m_contactHash[(*existing).ctcId].removeData((*existing).id);
				(*existing).m_data = newData;
				ctc.addData(*existing);
			}
			else
			{
				(*existing).m_data = newData;
				ctc.updateData(*existing);
			}
			return;
		}
		ClientContactData* cdata = new ClientContactData(newData);
		m_dataHash[cdata.id] = cdata;
		ctc.addData(cdata);
	}

	void handleTrimContactData(ContactId ctcId, usecs_t olderThan)
	{
		ClientContact* ctc = ctcId in m_contactHash;
		enforce(ctc !is null, "contact does not exist");
		ClientContactData*[] contactData = ctc.m_dataHash.values;
		foreach (ClientContactData* ccd; contactData)
		{
			if (ccd.time < olderThan)
			{
				ctc.removeData(ccd.id);
				m_dataHash.remove(ccd.id);
			}
		}
	}

	void handleContactUpdate(MsgT)(MsgT msg)
		if (isContactUpdateMsg!MsgT)
	{
		m_contactHash[msg.id].updateContact(msg);
	}

	void handleDropContact(ContactId id)
	{
		foreach (ClientContactData* ctd; m_contactHash[id].contactDataRange)
			m_dataHash.remove(ctd.id);
		m_contactHash[id].drop();
		m_contactHash.remove(id);
	}

	void handleDropData(int dataId)
	{
		if (dataId !in m_dataHash)
			return;
		ContactId ctcId = m_dataHash[dataId].ctcId;
		m_contactHash[ctcId].removeData(dataId);
		m_dataHash.remove(dataId);
	}

	void handleDropTracker(TrackerId tid)
	{
		ContactId cid = tid.ctcId;
		ClientContact cc = m_contactHash.get(cid, null);
		if (cc)
			cc.dropTracker(tid.sensorIdx);
	}

	void hadleMergeContact(ContactId srcId, ContactId destId)
	{
		assert(srcId != destId);
		ClientContact cs = m_contactHash[srcId];
		ClientContact cd = m_contactHash[destId];
		foreach (ClientContactData* ctd; cs.contactDataRange)
		{
			ctd.m_data.ctcId = destId;
			cd.addData(ctd);
		}
		cs.drop();
		m_contactHash.remove(srcId);
	}

	private int m_rayCronCounter = 0;

	/// Periodically call this to keep the list of rendered ray samples
	/// on the waterfall screen small. Effectively culls the tree.
	void rayDataHousekeeping()
	{
		m_rayCronCounter = (m_rayCronCounter + 1) % 20;
		if (m_rayCronCounter == 0)
		{
			usecs_t before = Game.simState.lastServerTime -
				(Waterfall.HEIGHT + 20) * 1000_000L;
			foreach (contact; m_contactHash.byValue)
				contact.trimRayTrees(before);
		}
	}
}


Button[] classifyAndDescribeContextButtons(ClientContact ctc)
{
	Button[] res;
	// classification
	Button[] classifications;
	Button btn;
	foreach (ctype; EnumMembers!ContactType)
	{
		btn = builder(new Button()).fontSize(15).content(ctype.to!string).build();
		btn.onClick += {
			Contact curContact = ctc.m_ctc;
			if (curContact.type != ctype)
			{
				Game.ciccon.sendMessage(
					immutable CICContactUpdateTypeReq(curContact.id, ctype));
			}
		};
		classifications ~= btn;
	}
	NestedContextBtn classifySubmenu = builder(new NestedContextBtn(classifications, 20)).
		fontSize(15).content("classify as").build();
	res ~= classifySubmenu;
	// description
	Button describebtn = builder(new Button()).fontSize(15).content(
		"describe").build();
	describebtn.onClick += {
		// we need to create new panel in the center of the screen
		// that allows to enter new contact description.
		Contact curContact = ctc.m_ctc;
		TextField descriptionTextField = builder(new TextField()).
			content(curContact.description).fontSize(25).fixedSize(vec2i(400, 30)).build;
		auto layout = vDiv([filler(),
			builder(hDiv([filler(), descriptionTextField, filler()])).fixedSize(vec2i(0, 30)).build,
			filler()]);
		Panel editPanel = new Panel(layout);
		Game.guiManager.addPanel(editPanel);
		descriptionTextField.onKbFocusLoss += ()
		{
			Game.guiManager.removePanel(editPanel);
		};
		descriptionTextField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyEscape)
				descriptionTextField.returnKbFocus();
			if (evt.code == sfKeyReturn)
			{
				// send description update
				string clampedDesc = descriptionTextField.content.str;
				if (clampedDesc.length > 128)
					clampedDesc.length = 128;
				CICContactUpdateDescriptionReq msg = CICContactUpdateDescriptionReq(
					curContact.id, clampedDesc);
				Game.ciccon.sendMessage(cast(immutable) msg);
			}
		};
		descriptionTextField.requestKbFocus();
		descriptionTextField.selectAll();
	};
	res ~= describebtn;
	return res;
}


/// Generate buttons, that contain common actions to perform on contact
Button[] commonContactContextMenu(ClientContact ctc)
{
	Button[] res;
	Button btn;
	res ~= classifyAndDescribeContextButtons(ctc);
	// trimming
	Button[] trimmingBtns;
	foreach (int secsToLeave; [30, 60, 180, 300, 900])
	{
		btn = builder(new TrimBtn(ctc.id, secsToLeave)).fontSize(15).
			content(secsToLeave.to!string ~ "s").build();
		trimmingBtns ~= btn;
	}
	NestedContextBtn trimSubmenu = builder(new NestedContextBtn(trimmingBtns, 20)).
		fontSize(15).content("trim to last").build();
	res ~= trimSubmenu;
	// drop
	btn = builder(new Button()).fontSize(15).content("drop contact").build();
	btn.onClick += {
		Game.ciccon.sendMessage(immutable CICDropContactReq(ctc.id));
	};
	res ~= btn;
	return res;
}

// workaround to D lambda capturing rules. Another solution:
// https://forum.dlang.org/post/imtygxgjovnvrrfmxpok@forum.dlang.org
private final class TrimBtn: Button
{
	private
	{
		ContactId m_ctcId;
		int m_secsToLeave;
	}

	this(ContactId ctcId, int secsToLeave)
	{
		super(ButtonType.SYNC);
		m_ctcId = ctcId;
		m_secsToLeave = secsToLeave;
		onClick += &processClick;
	}

	private void processClick()
	{
		auto msg = immutable CICTrimContactData(
			m_ctcId, Game.simState.lastServerTime - m_secsToLeave * 1000_000);
		Game.ciccon.sendMessage(msg);
	}
}
