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

module dsubs_client.tests;

import core.sync.mutex;

import std.conv: to;
import std.math: abs;
import std.experimental.logger;

import derelict.sfml2.graphics;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.render.render;
import dsubs_client.gui;

import dsubs_client.render.camera;


void runModuleTests()
{
	testCamera2D();
}

void testGuiElements()
{
	info("testGuiElements...");
	Window wnd = new Window("dsubs testGuiElements"d);
	InputRouter router = new InputRouter(wnd);
	GuiManager gui = new GuiManager(wnd);
	router.guiRouter = gui;
	Render render = new Render(wnd, router);
	render.guiRender = gui;

	Div row1 = builder(hDiv(
		[
			builder(new Label()).content("RED").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(255, 0, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.LEFT).vtextAlign(VTextAlign.TOP).build(),

			builder(new Label()).content("GREEN").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(0, 255, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).build(),

			builder(new Label()).content("BLUE").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(0, 0, 255, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.RIGHT).vtextAlign(VTextAlign.BOTTOM).build()
		]
	)).borderWidth(3).build();

	TextBox collapsableText = builder(new TextBox).content(copypasta).build;

	Div row2 = builder(hDiv(
		[
			builder(new Collapsable(collapsableText, "show/hide")).
				size(vec2i(180, 20)).headerFontSize(18).build(),
			builder(new PasswordField()).fontSize(28).content("TextField").build(),
			builder(new TextField()).fontSize(14).content("TextField").build()
		]
	)).borderWidth(3).build();

	auto label1 = builder(new Label()).fontSize(32).build();
	int btn1Counter = 0;
	int shiftDir = 1;
	auto button1 = builder(new Button(ButtonType.SYNC)).fontSize(32).
		content("Click me").build();
	button1.onClick += ()
	{
		btn1Counter += shiftDir;
		label1.content = btn1Counter.to!string;
	};
	auto button2 = builder(new Button(ButtonType.TOGGLE)).fontSize(32).
		content("Positive").build();
	button2.onClick += () {
		if (button2.state == ButtonState.ACTIVE)
		{
			button2.content = "Negative";
			shiftDir = -abs(shiftDir);
		}
		else
		{
			button2.content = "Positive";
			shiftDir = abs(shiftDir);
		}
	};
	auto button3 = builder(new Button(ButtonType.ASYNC)).fontSize(24).
		content("Activate x10").build();
	auto button4 = builder(new Button(ButtonType.SYNC)).fontSize(24).
		content("Deactivate x10").build();
	button3.onClick += ()
	{
		shiftDir *= 10;
	};
	button4.onClick += ()
	{
		if (button3.state == ButtonState.ACTIVE)
		{
			button3.signalClickEnd();
			shiftDir /= 10;
		}
	};

	Div row3 = builder(hDiv(
		[
			label1,
			button1,
			button2,
			builder(vDiv([button3, button4])).borderWidth(3).build()
		]
	)).borderWidth(3).build();

	Div guiDemoRoot = hDiv(
		[
			builder(vDiv([row1, row2, row3])).borderWidth(3).build,
			builder(new ScrollBar(builder(new TextBox).content(copypasta).build)).
				layoutType(LayoutType.FRACT).fraction(0.33f).build
		]);

	guiDemoRoot.borderWidth = 3;
	gui.addPanel(new Panel(guiDemoRoot));

	Mutex mutex = new Mutex();
	render.start(mutex);
	wnd.pollEvents(mutex);
	render.stop();
	wnd.close();
	info("OK");
}

immutable dstring copypasta = `The song "gucci gang" gave great meaning into my life. Lil pumps lyrics are nothing less of a genuine life lesson. People dont understand lil pumps story behind the lyrics. So i will do a lyric break down.

"Gucci gang, gucci gang, gucci gang, gucci gang (gucci gang) Gucci gang, gucci gang, gucci gang, gucci gang (gucci gang)"

Lil pump is telling his target audience that his gang is indeed called gucci gang. He says this in order to set the tone for the rest of the song and will show what his gang is all about.

"Spend three racks on a new chain (yuh) My bih luh do cocaine, ooh (ooh)"

Lil pump is explaining that his gang can in fact afford a chain that is $3,000. Lil pump is being humble and showing that even if he is rich, he will still pay money for a cheap chain. On the line: "my bih luh do cocaine, ooh (ooh)" Lil pump is alluding to the fact that his "bih" is on so much cocaine that she can barely speak which is why he says "bih" and "luh" instead of "bitch" and "love".

"I fuh a bih l, i forgot her name (brr, yuh) I can't buy a bitch no wedding ring (ooh) Rather go and buy balmains"

Lil pump is trying to say that he is not loyal at all and is trying to lower the chance of him getting a real girlfriend ever. All lil pump wants to do is fuck alot of women and try and avoid any std's.

"My lean cost more than your rent, ooh (it do)"

Lil pump is saying that he is willing to waste a large amount of money for drugs. Showing his more emotional side as he needs these drugs to get over that he failed school. The ad-lib helps the listener under stand that it actually does cost more than your rent.

"Me and my grandma take meds, ooh (huh?)"

Lil pump again is returning to his emotional side saying that his grandma is in fact a vegetable and she needs meds to survive. This makes lil pump very depressed so he aswell needs to take xanax for his depression.

"Fuck your airline fuck your company (fuck it)"

Lil pump was kicked off a plane just because he was screaming eskitit and somehow being "obnoxious" on the plane. I still dont know why he was kicked off. The only person that matters in the world is lil pump, who cares if people cant sleep or relax on a 24 hour flight.

"They kicked me out the plane off a percocet (brr) Now lil pump flyin' private jet (yuh) Everybody scream, "fuck westjet" (fuck em)"

Lil pump is alluding that he was kicked off the plane for using an illegal substance. This is entirely westjets fault. They should have either gave everyone drugs or kicked them all off except lil pump.

Thank you for reading and i hope you appreciate lil pumps artistry alot more now.`;