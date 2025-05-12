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
module dsubs_client.game.connections.cicserver;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.messages;
import dsubs_common.network.connection;

import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.protocol;
import dsubs_client.game.cic.server;
import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;


/// TCP connection from CIC server to client.
final class CICServerConnection: ProtocolConnection!CICProtocol
{
	this(CICServer cicserv, Socket sock, string expectedPw)
	{
		assert(expectedPw.length <= 64);
		super(sock);
		m_expectedPw = expectedPw;
		m_cicserv = cicserv;
		mixinHandlers(this);
	}

	private
	{
		string m_expectedPw;
		CICServer m_cicserv;
	}

	mixin Readonly!(bool, "authorized");
	mixin Readonly!(bool, "inSimFlow");

private:

	// just pass messages to CIC server, with minimal inSimFlow check.
	static string passToServerMixin(MsgT)(string serverHandlerName = null)
	{
		string conMethodName = "h_" ~ MsgT.stringof;
		serverHandlerName = serverHandlerName ? serverHandlerName : "handle" ~ MsgT.stringof;
		string res = "void " ~ conMethodName ~ "(" ~ MsgT.stringof ~ " req)";
		res ~= `{
			enforce(m_inSimFlow, "not in simulator flow");
			m_cicserv.` ~ serverHandlerName ~ `(req);
		}`;
		return res;
	}

	// pass inlined .req field of the message to backend connection of the CIC server.
	static string passToBackendMixin(MsgT)()
	{
		string conMethodName = "h_" ~ MsgT.stringof;
		string res = "void " ~ conMethodName ~ "(" ~ MsgT.stringof ~ " req)";
		res ~= `{
			enforce(m_inSimFlow, "not in simulator flow");
			m_cicserv.bcon.sendMessage(cast(immutable) req.req);
		}`;
		return res;
	}

	void h_loginReq(CICLoginReq req)
	{
		enforce(!m_authorized, "already authorized");
		enforce(req.password == m_expectedPw, "Wrong password");
		info("CIC peer connection authorized");
		immutable(ubyte)[] dbHash;
		synchronized(Game.mainMutexWriter)
		{
			dbHash = Game.entityDbHash;
		}
		sendMessage(immutable CICLoginRes(dbHash));
		m_authorized = true;
	}

	void h_entityDbReq(CICEntityDbReq req)
	{
		enforce(m_authorized, "unauthorized");
		EntityDbRes db;
		synchronized(Game.mainMutexWriter)
		{
			db = EntityDbRes(Game.entityDb);
		}
		sendMessage(cast(immutable CICEntityDbRes) db);
	}

	void h_enterSimFlowReq(CICEnterSimFlowReq req)
	{
		enforce(m_authorized, "unauthorized");
		enforce(!m_inSimFlow, "already in simulator flow");
		synchronized(m_cicserv.state.ctcMut)
		{
			if (m_cicserv.dead)
				throw new Exception("CIC server is dead");
			// required to wait on condition
			synchronized(m_cicserv.state.rsMut)
			{
				sendMessage(m_cicserv.state.awaitCicRecState());
				m_inSimFlow = true;
			}
			sendBytes(m_cicserv.state.serializeLastNData(1000));
		}
	}

	mixin(passToServerMixin!(CICThrottleReq));
	mixin(passToServerMixin!(CICCourseReq));
	mixin(passToServerMixin!(CICListenDirReq));
	mixin(passToServerMixin!(CICEmitPingReq));
	mixin(passToServerMixin!(CICCreateContactFromDataReq));
	mixin(passToServerMixin!(CICWireGuidanceActivateReq));
	mixin(passToServerMixin!(CICWireGuidanceUpdateParamsReq));

	mixin(passToServerMixin!(CICContactUpdateTypeReq)("handleCICContactUpdateReq"));
	mixin(passToServerMixin!(CICContactUpdateSolutionReq)("handleCICContactUpdateReq"));
	mixin(passToServerMixin!(CICContactUpdateDescriptionReq)("handleCICContactUpdateReq"));

	mixin(passToServerMixin!(CICContactDataReq));
	mixin(passToServerMixin!(CICDropContactReq));
	mixin(passToServerMixin!(CICDropDataReq));
	mixin(passToServerMixin!(CICContactMergeReq));
	mixin(passToServerMixin!(CICCreateContactFromHTrackerReq));
	mixin(passToServerMixin!(CICUpdateTrackerReq));
	mixin(passToServerMixin!(CICDropTrackerReq));
	mixin(passToServerMixin!(CICTrimContactData));
	mixin(passToServerMixin!(CICWireDesiredLengthReq));

	mixin(passToBackendMixin!(CICLoadTubeReq));
	mixin(passToBackendMixin!(CICSetTubeStateReq));
	mixin(passToBackendMixin!(CICLaunchTubeReq));
	mixin(passToBackendMixin!(CICPauseSimulatorReq));
	mixin(passToBackendMixin!(CICTimeAccelerationReq));
}