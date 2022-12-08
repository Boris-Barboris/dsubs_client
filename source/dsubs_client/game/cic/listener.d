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
module dsubs_client.game.cic.listener;

import std.socket;
import core.thread;

import dsubs_common.network.connection;
import dsubs_common.network.listener;

import dsubs_client.common;
import dsubs_client.game.connections.cicserver;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.protocol;


final class CICListener
{
	private
	{
		Thread publicEpThread;
		Socket publicSock;
		ushort cicPort = 17900;
		CICServerConnection[Object] allCons;
		CICServer m_cicserv;
		string m_password;
	}

	@property ushort port() const { return cicPort; }

	this(CICServer cicserv, string password)
	{
		m_password = password;
		m_cicserv = cicserv;
		publicEpThread = new Thread(&publicEndpoint);
	}

	void start()
	{
		synchronized(this)
		{
			while (cicPort < 17964)
			{
				try
				{
					TcpServer server = TcpServer("0.0.0.0", cicPort);
					publicSock = listenTcp(server);
					publicEpThread.start();
					info("CIC listening on ", cicPort);
					break;
				}
				catch (SocketOSException ex)
				{
					error("CIC listener start err: ", ex.msg);
					cicPort++;
				}
			}
			if (cicPort == 17964)
				throw new Exception(
					"Unable to start CIC listener due to port exhaustion");
		}
	}

	/// stop accepting new connections, close all opened ones
	void stop()
	{
		if (!publicSock)
			return;
		info("closing CIC listening socket");
		publicSock.shutdown(SocketShutdown.BOTH);
		publicSock.close();
		synchronized(this)
		{
			foreach (CICServerConnection c; allCons.byValue())
				c.close();
			allCons.clear();
		}
	}

	private void publicEndpoint()
	{
		serveTcp(publicSock, (Socket s)
			{
				auto con = new CICServerConnection(m_cicserv, s, m_password);
				synchronized(this)
				{
					allCons[con] = con;
				}
				con.onClose += cast(con.onClose.HandlerType) &removeCon;
				con.start();
			});
	}

	private void removeCon(CICServerConnection c)
	{
		synchronized(this)
		{
			allCons.remove(c);
		}
	}

	/// broadcast message to all clients in simulator flow
	void broadcast(immutable(ubyte)[] data)
	{
		synchronized(this)
		{
			foreach (CICServerConnection c; allCons.byValue())
			{
				if (c.inSimFlow)
					c.sendBytes(data);
			}
		}
	}

	/// ditto
	void broadcast(T)(immutable T msg)
		if (is(T == struct))
	{
		broadcast(CICProtocol.marshal(msg));
	}
}