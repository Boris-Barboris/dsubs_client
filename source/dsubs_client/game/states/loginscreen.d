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
module dsubs_client.game.states.loginscreen;

import std.utf;
import std.process: browse;
import std.datetime;

import core.thread;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api;
import dsubs_common.api.messages;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.core.settings;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loadout;
import dsubs_client.game.states.replay;
import dsubs_client.game.entities;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.messages;
import dsubs_client.game.connections.backend;
import dsubs_client.gui;


private
{
	enum int MENU_BUTTON_FONTSIZE = 50;
	enum int LOGIN_FONT_SIZE = 18;
	enum int INFO_FONT_SIZE = 18;
	enum float LOGIN_FRACT = 0.25f;
}


final class LoginScreenState: GameState
{
	private
	{
		bool canLogin, alreadySpawned;
		Label infoLabel;
		string m_coopAddr;
		Button connectButton, cicConnectButton, replayButton;
		void delegate() cicConnectCancellator;
		bool m_scenariosReceived;
		AvailableScenariosRes m_scenarios;
	}

	this(string coopAddr = null)
	{
		m_coopAddr = coopAddr;
	}

	override void setup()
	{
		Game.window.title = "dsubs";

		JSONValue config = readConfig();

		// we are in a short coop join mode
		if (m_coopAddr)
		{
			CICClientConnection.connectAsync(
				m_coopAddr, "",
				(CICClientConnection c)
				{
					synchronized(Game.mainMutexWriter)
					{
						Game.ciccon = c;
						info("stopping backend connection maintainer to focus on CIC");
						Game.bconm.stop();
						Game.window.title = "dsubs (coop client)";
					}
				},
				(Exception ex)
				{
					error(ex.msg);
					synchronized(Game.mainMutexWriter)
					{
						Game.window.stopEventProcessing();
					}
				});
			return;
		}

		int btnSize = (MENU_BUTTON_FONTSIZE * 1.3).lrint.to!int;
		connectButton = builder(new Button(ButtonType.ASYNC)).content("Authorize").
			backgroundColor(COLORS.simButtonBgnd).
			fontSize(MENU_BUTTON_FONTSIZE).build();

		replayButton = builder(new Button(ButtonType.ASYNC)).content("watch replay").
			backgroundColor(COLORS.simButtonBgnd).
			fontSize(LOGIN_FONT_SIZE).build();

		infoLabel = builder(new Label()).content("Connecting to server...").
			fontSize(INFO_FONT_SIZE).fixedSize(vec2i(400, INFO_FONT_SIZE + 10)).
			fontColor(COLORS.simMessageFont).htextAlign(HTextAlign.CENTER).build();

		int loginRowSize = (LOGIN_FONT_SIZE * 1.3).lrint.to!int;
		Label loginLabel = builder(new Label()).content("Login").
			htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).build();
		TextField loginField = builder(new TextField()).fontSize(LOGIN_FONT_SIZE).build();
		loginField.content = config.object.get("login", JSONValue("")).str;

		Label pwLabel = builder(new Label()).content("Password").
			htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).build();
		PasswordField pwField = builder(new PasswordField()).fontSize(LOGIN_FONT_SIZE).build();
		pwField.content = config.object.get("password", JSONValue("")).str;

		Div credDiv = builder(vDiv([
				loginLabel,
				loginField,
				pwLabel,
				pwField
			])).fixedSize(vec2i(0, loginRowSize * 4 + 20)).
			borderWidth(4).build();

		loginField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyTab)
				pwField.requestKbFocus();
			if (evt.code == sfKeyReturn)
				connectButton.simulateClick();
		};

		pwField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				connectButton.simulateClick();
		};

		connectButton.onClick += ()
		{
			if (!canLogin)
			{
				connectButton.signalClickEnd();
				return;
			}
			if (cicConnectCancellator)
			{
				cicConnectCancellator();
				cicConnectCancellator = null;
			}
			info("authorizing with login ", loginField.content.str);
			Game.bconm.con.sendMessage(
				immutable LoginReq(
					loginField.content.str.encrypt,
					pwField.content.str.encrypt));
			infoLabel.content = "Authorizing...";
			writeConfigField("login", loginField.content.str);
			writeConfigField("password", pwField.content.str);
		};

		replayButton.onClick += ()
		{
			ReplayState.s_currentSimId = "main_arena";
			Game.bconm.con.sendMessage(immutable ReplayGetDataReq("main_arena",
				(cast(Date) Clock.currTime).toISOExtString()));
		};

		Label cicIpLabel = builder(new Label()).content("coop IP:").
			htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).
			fraction(LOGIN_FRACT).build();
		TextField cicIpField = builder(new TextField()).fontSize(LOGIN_FONT_SIZE).build();
		cicIpField.content = config.object.get(
			"coopaddr", JSONValue("localhost:17900")).str;

		Label orLabel = builder(new Label()).content("OR").
			htextAlign(HTextAlign.CENTER).fontSize(MENU_BUTTON_FONTSIZE / 2).
			fixedSize(vec2i(0, (MENU_BUTTON_FONTSIZE / 1.5).lrint.to!int)).build();

		Div cicDiv = builder(hDiv([cicIpLabel, cicIpField, filler(LOGIN_FRACT)])).
			fixedSize(vec2i(0, loginRowSize)).build();

		cicConnectButton = builder(new Button(ButtonType.ASYNC)).
			content("Connect to another window").
			backgroundColor(COLORS.simButtonBgnd).
			fontSize(MENU_BUTTON_FONTSIZE / 2).fixedSize(vec2i(200, btnSize / 2)).build();

		cicConnectButton.onClick += ()
		{
			if (cicConnectCancellator)
			{
				cicConnectButton.signalClickEnd();
				return;
			}
			cicConnectCancellator = CICClientConnection.connectAsync(
				cicIpField.content.str, "",
				(CICClientConnection c)
				{
					synchronized(Game.mainMutexWriter)
					{
						Game.ciccon = c;
						cicConnectButton.signalClickEnd();
						cicConnectCancellator = null;
						info("stopping backend connection maintainer to focus on CIC");
						Game.bconm.stop();
						infoLabel.content = "Connected to coop server";
						Game.window.title = "dsubs (coop client)";
					}
				},
				(Exception ex)
				{
					error(ex.msg);
					synchronized(Game.mainMutexWriter)
					{
						infoLabel.content = ex.msg;
						cicConnectButton.signalClickEnd();
						cicConnectCancellator = null;
					}
				});
			writeConfigField("coopaddr", cicIpField.content.str);
		};

		Div mainMenuDiv = builder(vDiv([
			filler(),
			credDiv,
			filler(20),
			builder(hDiv([filler(60), connectButton, filler(60)])).
				fixedSize(vec2i(10, btnSize)).build(),
			filler(10),
			infoLabel,
			filler(10),
			builder(hDiv([filler(100), replayButton, filler(100)])).
				fixedSize(vec2i(10, 30)).build(),
			filler(40),
			orLabel,
			filler(40),
			cicConnectButton,
			filler(20),
			cicDiv,
			filler()
		])).fixedSize(vec2i(400, 10)).build();

		Div mainMenuLayout = hDiv([
			filler(),
			mainMenuDiv,
			filler()
		]);

		Game.guiManager.addPanel(new Panel(mainMenuLayout));
		loginField.requestKbFocus();

		// cleanup connections state
		if (Game.ciccon)
			Game.ciccon.close();
		resetBackConM();
	}

	void handleServerStatus(ServerStatusRes res)
	{
		if (res.apiVersion != ServerStatusRes.init.apiVersion)
		{
			string errorStr = "Incompatible API versions, client " ~
				ServerStatusRes.init.apiVersion.to!string ~
				", server " ~ res.apiVersion.to!string;
			error(errorStr);
			infoLabel.content = errorStr;
			if (res.apiVersion > ServerStatusRes.init.apiVersion)
			{
				try
				{
					browse("https://github.com/Boris-Barboris/dsubs_demo/releases");
				}
				catch (Exception ex)
				{
					error(ex.toString());
				}
			}
			return;
		}
		canLogin = true;
		infoLabel.content = res.playersOnline.to!string ~ " players online";
		// Game.bconm.con.sendMessage(immutable ReplayGetDataReq("main_arena", "2020-02-25"));
	}

	void handleLoginSuccess(LoginSuccessRes res)
	{
		info("login successfull");
		canLogin = false;
		m_scenariosReceived = false;
		Game.entityDbHash = res.dbHash;
		infoLabel.content = "Requesting entity database";
		Game.bconm.con.sendMessage(immutable EntityDbReq());
		// connect secondary audio socket
		Game.bconm.startSecondary(res.secondaryConnectionSecret);
		// check if we are already swimming out there on the server
		if (res.alreadySpawned)
		{
			info("Player is already spawned");
			alreadySpawned = true;
		}
		else
			alreadySpawned = false;
		connectButton.signalClickEnd();
	}

	void handleLoginFailure(LoginFailureRes res)
	{
		infoLabel.content = "Unable to log in: " ~ res.reason;
		connectButton.signalClickEnd();
	}

	override void handleAvailableScenariosRes(AvailableScenariosRes res)
	{
		m_scenarios = res;
		m_scenariosReceived = true;
	}

	// will arrive after AvailableScenariosRes.
	void handleEntityDb(EntityDbRes res)
	{
		info("entity db received");
		Game.setEntityDb(res.entityDb);
		// when we've got entitydb we always reconnect.
		if (alreadySpawned)
			Game.bconm.con.sendMessage(immutable ReconnectReq());
		else
		{
			assert(m_scenariosReceived);
			Game.activeState = new LoadoutState(&m_scenarios);
		}
	}

	override void handleBackendDisconnect()
	{
		canLogin = alreadySpawned = false;
		infoLabel.content = "Connecting to server...";
		connectButton.signalClickEnd();
	}

	private void resetBackConM()
	{
		Game.bconm.stop();
		Game.bconm = new BackendConMaintainer();
		Game.bconm.start();
	}

	override void handleCICDisconnect()
	{
		cicConnectCancellator = null;
		cicConnectButton.signalClickEnd();
	}
}