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
module dsubs_client.game.waterfall;

import std.algorithm.comparison: min, max;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.math;
import dsubs_common.containers.circqueue;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.lib.openal: StreamingSoundSource;
import dsubs_client.lib.sfml: tosf;
import dsubs_client.render.camera;
import dsubs_client.render.shapes;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game;


private
{
	enum int HEADER_FONT_SIZE = 16;
	enum int HEADER_SECTION_HEIGHT = 26;
	enum int VOLUME_SECTION_WIDTH = 300;
}


struct WaterfallGui
{
	Div root;
	Waterfall wf;
	Slider volumeSlider;
	Button normalizationToggle;
}


WaterfallGui createWaterfallPanel(const HydrophoneTemplate ht, int hydrophoneIndex)
{
	WaterfallGui res;
	res.wf = new Waterfall(ht, hydrophoneIndex);
	Slider volumeSlider = new Slider();
	volumeSlider.value = 0.66f;

	Button normalizationToggle = builder(new Button()).content("Normalization ON").
		fontSize(15).fixedSize(vec2i(140, 0)).build();

	static float sliderToGain(float sliderValue)
	{
		sliderValue = (sliderValue - 0.5f) * 2;
		return toLinear(sliderValue * toDb(short.max / 200));
	}

	static float sliderToNormalizationTarget(float sliderValue)
	{
		return -30.0f + sliderValue * 30.0f;
	}

	normalizationToggle.onClick += ()
		{
			StreamingSoundSource soundStreamer = Game.simState.
				sonarSounds[hydrophoneIndex];
			if (!soundStreamer.normalize)
			{
				soundStreamer.normalizationTarget = sliderToNormalizationTarget(
					volumeSlider.value);
				soundStreamer.normalize = true;
				normalizationToggle.content = "Normalization ON";
			}
			else
			{
				soundStreamer.normalize = false;
				normalizationToggle.content = "Normalization OFF";
				volumeSlider.value = 0.5f;
			}
		};

	volumeSlider.onValueChanged += (float newVal)
		{
			StreamingSoundSource soundStreamer = Game.simState.
				sonarSounds[hydrophoneIndex];
			if (soundStreamer.normalize)
			{
				soundStreamer.normalizationTarget = sliderToNormalizationTarget(
					volumeSlider.value);
			}
			else
			{
				if (newVal == 0.0f)
					soundStreamer.gain = 0.0f;
				else
					soundStreamer.gain = sliderToGain(newVal);
			}
		};

	Div volumeDiv = builder(hDiv([
		builder(new Label()).content("Volume:").fontSize(HEADER_FONT_SIZE).
			layoutType(LayoutType.CONTENT).build(),
		volumeSlider,
		normalizationToggle
	])).fixedSize(vec2i(VOLUME_SECTION_WIDTH, HEADER_SECTION_HEIGHT)).build;

	Div header = builder(hDiv([
		volumeDiv,
		filler()
	])).fixedSize(vec2i(0, HEADER_SECTION_HEIGHT)).mouseTransparent(false).build;

	res.root = builder(vDiv([
		filler(5),
		header,
		res.wf
	])).backgroundColor(COLORS.simPanelBgnd).mouseTransparent(false).build;
	res.volumeSlider = volumeSlider;
	res.normalizationToggle = normalizationToggle;

	return res;
}


/// Common code for Waterfall and SonarDisplay, related to panoramic
/// cylindrical coordinate mapping
class PanoramicDisplay(DataIntType): GuiElement
{
	protected
	{
		/// height of compass part of the header
		int m_compassHeight;
		/// full height of the header, including compass and all other elements
		int m_headerHeight;

		// render target to write pixel data to. 0 pixel column is just after (right from it)
		// 180 course, last pixel column is just before 180 course (left from it).
		// 0 to $-1 is clockwise rotation.
		sfRenderTexture* m_renderTexture;
		int m_width;	/// width of m_renderTexture
		int m_height;	/// height of m_renderTexture
		float m_pxperrad;		/// x scale between world space and renderTexture space
		float m_pyperworldy;	/// y scale between world space and renderTexture space
		/// camera is used to control zooming and panning over renderTexture and
		/// generate texture coordinates for m_vertices.
		Camera2D m_camera;
		int m_camViewportWidth;		/// width of camera viewport on 1.0 zoom
		int m_camViewportHeight;	/// height of camera viewport on 1.0 zoom
		float m_zoomSpd = 0.14f;	/// zoom sensitivity gain
		/// vertices that render m_renderTexture on the screen
		sfVertex[6] m_vertices;

		/// vertex array for rendering rows on top of m_renderTexure using lines
		sfVertex[] m_stage;

		__gshared const sfRenderStates s_states =
			sfRenderStates(sfBlendAlpha, sfTransform_Identity);

		/// compass background
		sfRectangleShape* m_headerRect;
		Label[4] m_compassLabels;
		Label m_underCursorLabel;
	}

	@property Camera2D camera() { return m_camera; }

	@property void camera(Camera2D rhs)
	{
		m_camera = rhs;
		onCameraChangeDefault();
	}

	private PanoramicOverlay m_overlay;

	/// For normalized data [0, 1] this level and darker will be rendered as black.
	float blackLevel = 0.0f;

	struct PanoramicParams
	{
		int compassHeight = 24;
		int headerHeight = 24;
		int width = 360 * 8;
		int height = -1;
		int camViewPortWidth = 360 * 8;
		int camViewPortHeight = -1;
		bool additionalRow = true;
	}

	this(PanoramicParams params, PanoramicOverlay overlay)
	{
		assert(overlay !is null);
		m_overlay = overlay;
		mouseTransparent = false;
		m_width = params.width;
		assert(m_width > 0);
		m_height = params.height;
		assert(m_height > 0);
		m_camViewportWidth = params.camViewPortWidth;
		assert(m_camViewportWidth > 0);
		m_camViewportHeight = params.camViewPortHeight;
		assert(m_camViewportHeight > 0);
		m_compassHeight = params.compassHeight;
		m_headerHeight = params.headerHeight;
		m_pxperrad = m_width / (PI * 2);

		// 1 pixel higher than m_height to support waterfall streaming
		m_renderTexture = sfRenderTexture_create(m_width,
			params.additionalRow ? m_height + 1 : m_height, false);
		sfRenderTexture_setActive(m_renderTexture, sfTrue);
		sfRenderTexture_clear(m_renderTexture, sfBlack);
		sfRenderTexture_setRepeated(m_renderTexture, sfTrue);
		sfRenderTexture_setActive(m_renderTexture, sfFalse);

		m_camera = new Camera2D(vec2ui(m_camViewportWidth, m_camViewportHeight), false);
		m_camera.pan(vec2d(m_width * 0.5, m_height * 0.5));

		// m_vertices form a rectanglular area to draw broadband data to
		m_vertices[0] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[1] = sfVertex(sfVector2f(1, 0), sfWhite, sfVector2f(m_width, 0));
		m_vertices[2] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(m_width, m_height));
		m_vertices[3] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[4] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(m_width, m_height));
		m_vertices[5] = sfVertex(sfVector2f(0, 1), sfWhite, sfVector2f(0, m_height));
		foreach (ref sfVertex v; m_vertices)
			v.position.y = m_headerHeight;
		updateTexCoords();

		// compass
		int compassFontSize = m_compassHeight - 4;
		m_headerRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_headerRect, 0.0f);
		sfRectangleShape_setFillColor(m_headerRect, sfBlack);
		sfRectangleShape_setPosition(m_headerRect, sfVector2f(0, 0));
		for (int i = 0; i < 4; i++)
		{
			Label lbl = new Label();
			lbl.fontSize = compassFontSize;
			lbl.size = vec2i(40, m_compassHeight);
			lbl.fontColor = sfWhite;
			lbl.htextAlign = HTextAlign.CENTER;
			lbl.content = (i * 90).to!string;
			lbl.parent = this;
			lbl.parentViewport = &viewport();
			m_compassLabels[i] = lbl;
		}
		m_underCursorLabel = builder(new Label()).fontSize(compassFontSize).
			size(vec2i(150, m_compassHeight)).fontColor(sfYellow).
			htextAlign(HTextAlign.CENTER).build();
		m_underCursorLabel.parent = this;
		m_underCursorLabel.parentViewport = &viewport();

		onCameraChange += &onCameraChangeDefault;
	}

	override void onHide()
	{
		super.onHide();
		m_overlay.onHide();
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (rectContainsPoint(x, y))
		{
			GuiElement res = m_overlay.getFromPoint(evt, x, y);
			if (res)
				return res;
			return this;
		}
		return null;
	}

	~this()
	{
		sfRenderTexture_destroy(m_renderTexture);
		sfRectangleShape_destroy(m_headerRect);
	}

	/// screen-space height of the area to draw renderTexture to
	final @property int contentHeight() const
	{
		return max(0, size.y - m_headerHeight);
	}

	/// draw one row of data to renderTexture.
	protected final void drawRow(const(DataIntType)[] data, float ytexture, float sectorAngle,
		float sectorCenterBearing)
	{
		sectorCenterBearing = clampAnglePi(sectorCenterBearing);
		m_stage.length = data.length * 2;
		float x = m_width / 2.0f - m_pxperrad * (sectorCenterBearing + sectorAngle / 2);
		float dx = m_pxperrad * sectorAngle / data.length;
		assert(dx > 0.0f);
		if (x < 0.0f)
			x += m_width;
		if (x > m_width)
			x -= m_width;
		for (size_t i = 0, j = 0; i < data.length; i++, j += 2)
		{
			float brightness = min(1.0f,
				max(0.0f, float(data[i]) / DataIntType.max - blackLevel));
			ubyte brt = lrint(brightness / (1 - blackLevel) * ubyte.max).to!ubyte;
			sfColor color = sfColor(brt, brt, brt, 255);
			m_stage[j].position = sfVector2f(x, ytexture);
			m_stage[j].color = color;
			x += dx;
			if (x > m_width)
			{
				// we have a special case of wraparound
				m_stage[j + 1].position = sfVector2f(m_width, ytexture);
				m_stage[j + 1].color = color;
				x -= m_width;
				m_stage.length += 2;
				m_stage[$ - 2].position = sfVector2f(0, ytexture);
				m_stage[$ - 2].color = color;
				m_stage[$ - 1].position = sfVector2f(x, ytexture);
				m_stage[$ - 1].color = color;
			}
			else
			{
				m_stage[j + 1].position = sfVector2f(x, ytexture);
				m_stage[j + 1].color = color;
			}
		}
		sfRenderTexture_setActive(m_renderTexture, sfTrue);
		sfRenderTexture_drawPrimitives(m_renderTexture, m_stage.ptr,
			m_stage.length, sfLines, &s_states);
		sfRenderTexture_setActive(m_renderTexture, sfFalse);
	}

	protected final void clearRow(float ytexture, sfColor color = sfBlack)
	{
		sfVertex[2] blackLine = [sfVertex(sfVector2f(0, ytexture), sfBlack),
			sfVertex(sfVector2f(m_width, ytexture), sfBlack)];
		sfRenderTexture_setActive(m_renderTexture, sfTrue);
		sfRenderTexture_drawPrimitives(m_renderTexture, blackLine.ptr,
			2, sfLines, &s_states);
		sfRenderTexture_setActive(m_renderTexture, sfFalse);
	}

	Event!(void delegate()) onCameraChange;

	protected void onCameraChangeDefault()
	{
		constraintCamera();
		updateTexCoords();
		updateHeaderElements();
	}

	/// Dirty hack to rebuild view from external camera
	final void onShowRebuildFromCamera()
	{
		onCameraChangeDefault();
	}

	// subscribe to events of all other displays, that are not this
	void synchronizeCameraWith(typeof(this)[] otherDisplays)
	{
		foreach (disp; otherDisplays)
			if (disp !is this)
				disp.onCameraChange += &onCameraChangeDefault;
	}

	private void constraintCamera()
	{
		double overtop = -m_camera.transform2world(vec2d(0, 0)).y;
		if (overtop > 0.0)
			m_camera.pan(vec2d(0, overtop));
		double underbot = m_camera.transform2world(vec2d(0, m_camViewportHeight)).y - m_height;
		if (underbot > 0.0)
			m_camera.pan(vec2d(0, -underbot));
	}

	override void updatePosition()
	{
		super.updatePosition();
		updateHeaderElements();
		m_overlay.position = vec2i(position.x, position.y + m_headerHeight);
	}

	override void updateSize()
	{
		super.updateSize();
		sfRectangleShape_setSize(m_headerRect, sfVector2f(size.x, m_headerHeight));
		m_vertices[1].position.x = m_vertices[2].position.x =
			m_vertices[4].position.x = size.x;
		m_vertices[2].position.y = m_vertices[4].position.y =
			m_vertices[5].position.y = size.y;
		updateHeaderElements();
		m_overlay.size = vec2i(size.x, contentHeight);
	}

	/// update vertex texture coordinates from camera transform
	protected void updateTexCoords()
	{
		vec2d ul = m_camera.transform2world(vec2d(0.0, 0.0));
		vec2d br = m_camera.transform2world(vec2d(m_camViewportWidth, m_camViewportHeight));
		// x
		m_vertices[0].texCoords.x = m_vertices[3].texCoords.x =
			m_vertices[5].texCoords.x = ul.x;
		m_vertices[1].texCoords.x = m_vertices[2].texCoords.x =
			m_vertices[4].texCoords.x = br.x;
		// y
		m_vertices[0].texCoords.y = m_vertices[1].texCoords.y =
			m_vertices[3].texCoords.y = ul.y;
		m_vertices[2].texCoords.y = m_vertices[4].texCoords.y =
			m_vertices[5].texCoords.y = br.y;
	}

	// bearing to pixel in screen space
	protected final float bearingToPixel(float bearing)
	{
		float camCoord = m_camera.transform2screen(
			vec2d(m_width / 2.0f - m_pxperrad * bearing, 0)).x;
		float fullRotationCam = m_width * m_camera.zoom;
		if (camCoord < 0.0f)
			camCoord = fullRotationCam + fmod(camCoord, fullRotationCam);
		else
			camCoord = fmod(camCoord, fullRotationCam);
		return camCoord * size.x / m_camViewportWidth;
	}

	protected final float pixelToBearing(float px)
	{
		float tx = m_vertices[0].texCoords.x + (float(px) / size.x) *
			(m_vertices[1].texCoords.x - m_vertices[0].texCoords.x);
		return PI - tx / m_pxperrad;
	}

	protected void updateHeaderElements()
	{
		// compass
		for (int i = 0; i < 4; i++)
		{
			float bearing = dgr2rad(-i * 90);
			int lblPosX = lrint(bearingToPixel(bearing)).to!int -
				m_compassLabels[i].size.x / 2;
			m_compassLabels[i].position = vec2i(position.x + lblPosX, position.y);
		}
	}

	protected void updateCursorLabel(int relCursorX, int relCursorY)
	{
		import std.format;

		float bearing = clampAnglePi(pixelToBearing(relCursorX));
		int lblPosX = lrint(bearingToPixel(bearing)).to!int -
				m_underCursorLabel.size.x / 2;
		m_underCursorLabel.position = vec2i(position.x + lblPosX, position.y);
		dmutstring labelContent = m_underCursorLabel.content;
		int bearingInt = lrint(-compassAngle(bearing).rad2dgr).to!int;
		auto rw = mutstringRewriter(labelContent);
		formattedWrite!"%d"(rw, bearingInt);
		m_underCursorLabel.content = rw.get();
	}

	protected void drawHeaderShapes(Window wnd, long usecsDelta)
	{
		m_sfRst.texture = null;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_headerRect, &m_sfRst);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		drawHeaderShapes(wnd, usecsDelta);
		m_sfRst.texture = sfRenderTexture_getTexture(m_renderTexture);
		sfRenderWindow_drawPrimitives(wnd.wnd, m_vertices.ptr, 6, sfTriangles,
			&m_sfRst);
		foreach (l; m_compassLabels)
			l.draw(wnd, usecsDelta);
		m_underCursorLabel.draw(wnd, usecsDelta);
		m_overlay.draw(wnd, usecsDelta);
	}

	/// Overlay for PanoramicElement
	class PanoramicOverlay: Overlay
	{
		override double world2screenRot(double world) { return world; }
		override double screen2worldRot(double screen) { return screen; }
		override double world2screenLength(double world) { return world; }
		override double screen2worldLength(double screen) { return screen; }

		this()
		{
			mouseTransparent = false;
			// mouse and keyboard handlers
			onMouseDown += &processMouseDown;
			onMouseUp += &processMouseUp;
			onMouseMove += &processMouseMove;
			onMouseScroll += &processMouseScroll;
		}

		protected
		{
			int m_mousePrevX, m_mousePrevY;
			bool m_panned;	/// true when mouse has moved since RMB down
			int m_panDist = 0;	// allow small jitter for right click
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
			m_panDist = 0;
		}

		private void processMouseUp(int x, int y, sfMouseButton btn)
		{
			if (btn == sfMouseRight)
				returnMouseFocus();
		}

		private void processMouseMove(int x, int y)
		{
			if (mouseFocused)
				onPan(x, y);
			else
				updateCursorLabel(x - position.x, y - position.y);
		}

		override void onPan(int x, int y)
		{
			if (m_mousePrevX != x || m_mousePrevY != y)
			{
				m_panned = true;	// we have moved the mouse
				m_panDist += abs(x - m_mousePrevX);
				m_panDist += abs(y - m_mousePrevY);
			}
			m_camera.pan(
				vec2d(double(m_mousePrevX - x) / size.x * m_camViewportWidth,
						double(m_mousePrevY - y) / size.y * m_camViewportHeight)
					/ m_camera.zoom);
			onCameraChange();
			m_mousePrevX = x;
			m_mousePrevY = y;
			updateCursorLabel(x - position.x, y - position.y);
		}

		private void processMouseScroll(int x, int y, float delta)
		{
			double oldZoom = m_camera.zoom;
			m_camera.zoom = max(1.0, min(16.0, m_camera.zoom * (1 + m_zoomSpd * delta)));
			if (delta > 0)
			{
				float ux = m_camViewportWidth * ((x - position.x) / float(size.x) - 0.5f);
				float uy = m_camViewportHeight * ((y - position.y) / float(size.y) - 0.5f);
				vec2d zoomPivot = 1.2f * vec2d(ux, uy);
				vec2d topan = zoomPivot / oldZoom - zoomPivot / m_camera.zoom;
				m_camera.pan(topan);
			}
			onCameraChange();
		}
	}
}


/// Zoomable waterfall display for hydrophone data
final class Waterfall: PanoramicDisplay!ushort
{
	private
	{
		const HydrophoneTemplate m_ht;
		const int m_hydrophoneIdx;
		// microphone director
		sfCircleShape* m_directorCircle;
		float m_listenDir = 0.0;
		int m_dirHeaderHeight = 18;
		/// in waterfall render texture is sliding from top to bottom cyclically.
		int m_vertPos;
		TrackerOverlay m_trackerOverlay;
		/// Circular buffer to contain history of ray origins
		CircQueue!(vec2d, true) m_originQueue;

		WaterfallOverlay m_overlay;
	}

	enum int HEIGHT = 60 * 5;

	@property WaterfallOverlay overlay() { return m_overlay; }

	@property int hydrophoneIdx() const { return m_hydrophoneIdx; }

	@property TrackerOverlay trackerOverlay() { return m_trackerOverlay; }

	this(const HydrophoneTemplate ht, int hydrophoneIdx)
	{
		m_ht = ht;
		m_hydrophoneIdx = hydrophoneIdx;
		PanoramicParams params;
		params.headerHeight = params.compassHeight + m_dirHeaderHeight;
		params.height = HEIGHT;		// 5 minutes
		params.camViewPortHeight = params.height;
		m_originQueue = CircQueue!(vec2d, true)(params.height.to!size_t);
		blackLevel = 0.1f;
		m_pyperworldy = 1.0f;		// 1 pixel = 1 second
		m_overlay = new WaterfallOverlay();
		super(params, m_overlay);
		m_vertPos = -m_height - 1;
		m_trackerOverlay = new TrackerOverlay();
		m_trackerOverlay.onMouseScroll += &m_overlay.processMouseScroll;

		// director
		m_directorCircle = sfCircleShape_create();
		sfCircleShape_setPointCount(m_directorCircle, 3);
		sfCircleShape_setRotation(m_directorCircle, 180.0f);
		sfCircleShape_setRadius(m_directorCircle, m_dirHeaderHeight / 3);
		sfCircleShape_setFillColor(m_directorCircle, sfWhite);
		sfCircleShape_setOutlineThickness(m_directorCircle, 0.0f);
		sfFloatRect bounds = sfCircleShape_getLocalBounds(m_directorCircle);
		sfCircleShape_setOrigin(m_directorCircle,
			sfVector2f(bounds.left + bounds.width / 2, bounds.top));
	}

	~this()
	{
		sfCircleShape_destroy(m_directorCircle);
	}

	override void updatePosition()
	{
		super.updatePosition();
		m_trackerOverlay.position = vec2i(position.x, position.y + m_compassHeight);
	}

	override void updateSize()
	{
		super.updateSize();
		m_trackerOverlay.size = vec2i(size.x, m_dirHeaderHeight);
	}

	override void onHide()
	{
		super.onHide();
		m_trackerOverlay.onHide();
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (rectContainsPoint(x, y))
		{
			GuiElement res = m_overlay.getFromPoint(evt, x, y);
			if (res)
				return res;
			res = m_trackerOverlay.getFromPoint(evt, x, y);
			if (res)
				return res;
			return this;
		}
		return null;
	}

	void drawData(const(ushort)[] data, double subWrot, int antIdx)
	{
		float row = m_vertPos < 0 ? -m_vertPos - 0.5f : m_height + 0.5f;
		drawRow(data, row, m_ht.fov, subWrot + m_ht.antRots[antIdx]);
	}

	// draw black line to zero out the next row we will render into.
	void completeRow(vec2d* sensorPosition)
	{
		if (sensorPosition)
			m_originQueue.pushBack(*sensorPosition);
		else
			if (m_originQueue.length > 0)
				m_originQueue.pushBack(m_originQueue.fromBack(0));
			else
				m_originQueue.pushBack(Game.simState.playerSub.transform.wposition);
		sfRenderTexture_display(m_renderTexture);
		m_vertPos++;
		if (m_vertPos > 0)
			m_vertPos -= m_height + 1;
		float row = m_vertPos < 0 ? -m_vertPos - 0.5f : m_height + 0.5f;
		clearRow(row);
		updateTexCoords();
	}

	float pixelToDelay(float px)
	{
		if (contentHeight <= 0)
			return 0.0f;
		float camCoord = px * m_camViewportHeight / contentHeight;
		return m_camera.transform2world(vec2d(0, camCoord)).y;
	}

	float delayToPixel(float delay)
	{
		float camCoord = m_camera.transform2screen(vec2d(0, delay + 0.5f)).y;
		return camCoord * contentHeight / m_camViewportHeight;
	}

	final class WaterfallOverlay: PanoramicOverlay
	{
		this()
		{
			onMouseUp += &processMouseUp;
		}

		/// world.x is bearing, world.y is age of data in seconds.
		override vec2d world2screenPos(vec2d world)
		{
			return position +
				vec2d(
					bearingToPixel(world.x),
					this.outer.delayToPixel(world.y)
				);
		}

		override vec2d screen2worldPos(vec2d screen)
		{
			vec2d local = screen - position;
			return vec2d(
				pixelToBearing(local.x),
				this.outer.pixelToDelay(local.y)
			);
		}

		private void processMouseUp(int x, int y, sfMouseButton btn)
		{
			if (btn == sfMouseLeft)
			{
				this.outer.updateDirectorElement(x - position.x);
				Game.ciccon.sendMessage(immutable CICListenDirReq(
					this.outer.m_hydrophoneIdx, this.outer.m_listenDir));
			}
			if (btn == sfMouseRight && m_panDist < 3)
				spawnContextMenu(x, y);
		}

		/// Returns false if no memory of this origin is in the internal circular buffer.
		/// Does not interpolate.
		bool getOrigin(usecs_t atTime, ref vec2d origin)
		{
			long delay = (Game.simState.lastServerTime - atTime) / 1000_000L;
			if (delay < 0 || delay >= this.outer.m_originQueue.length)
				return false;
			origin = this.outer.m_originQueue.fromBack(delay.to!size_t);
			return true;
		}

		private void spawnContextMenu(int x, int y)
		{
			int xlocal = x - position.x;
			int ylocal = y - position.y;
			float bearing = pixelToBearing(xlocal);
			float delay = this.outer.pixelToDelay(ylocal);
			size_t delayIdx = delay.to!size_t;
			if (delayIdx < this.outer.m_originQueue.length)
			{
				vec2d rayOrigin = this.outer.m_originQueue.fromBack(delayIdx);
				RayData rayData = RayData(rayOrigin, bearing);
				ContactDataUnion cdu = { ray: rayData };
				CICCreateContactFromDataReq req = CICCreateContactFromDataReq(
					'E',
					ContactData(
						-1,
						ContactId(),
						Game.simState.lastServerTime - delayIdx * 1000_000L,
						DataSource(DataSourceType.Hydrophone, this.outer.m_hydrophoneIdx),
						DataType.Ray,
						cdu));
				Button[] buttons = [
						builder(new Button()).fontSize(15).content("new contact").build()
				];
				buttons[0].onClick += () {
					Game.ciccon.sendMessage(cast(immutable) req);
				};
				ContextMenu menu = contextMenu(
						Game.guiManager,
						buttons,
						Game.window.size,
						vec2i(x, y),
						20);
			}
		}
	}

	override void updateTexCoords()
	{
		super.updateTexCoords();
		foreach (ref sfVertex vertex; m_vertices)
			vertex.texCoords.y -= m_vertPos;
	}

	override void updateHeaderElements()
	{
		super.updateHeaderElements();
		float dirX = bearingToPixel(m_listenDir);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(dirX, m_compassHeight + m_dirHeaderHeight));
	}

	@property void listenDir(float rhs)
	{
		m_listenDir = rhs;
		float dirX = bearingToPixel(m_listenDir);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(dirX, m_compassHeight + m_dirHeaderHeight));
	}

	private void updateDirectorElement(int relCursorX)
	{
		m_listenDir = pixelToBearing(relCursorX);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(relCursorX, m_compassHeight + m_dirHeaderHeight));
	}

	override void drawHeaderShapes(Window wnd, long usecsDelta)
	{
		super.drawHeaderShapes(wnd, usecsDelta);
		m_trackerOverlay.draw(wnd, usecsDelta);
		sfRenderWindow_drawCircleShape(wnd.wnd, m_directorCircle, &m_sfRst);
	}

	override void updateCursorLabel(int relCursorX, int relCursorY)
	{
		import std.format;

		float worldBearing = clampAnglePi(pixelToBearing(relCursorX));
		float delay = pixelToDelay(relCursorY);
		int lblPosX = lrint(bearingToPixel(worldBearing)).to!int -
				m_underCursorLabel.size.x / 2;
		m_underCursorLabel.position = vec2i(position.x + lblPosX, position.y);
		dmutstring labelContent = m_underCursorLabel.content;
		auto rw = mutstringRewriter(labelContent);
		formattedWrite!"%d, %dsec"(rw, -worldBearing.compassAngle.rad2dgr.to!int, -delay.to!int);
		m_underCursorLabel.content = rw.get();
	}

	/// Small overlay, located in display header, occupied by tracker and peak elements
	final class TrackerOverlay: Overlay
	{
		override void onPanStart(int x, int y) {}
		override void onPan(int x, int y) {}
		override double world2screenRot(double world) { return world; }
		override double screen2worldRot(double screen) { return screen; }
		override double world2screenLength(double world) { return world; }
		override double screen2worldLength(double screen) { return screen; }

		private PeakOverlayElement[] m_peaks;

		this()
		{
			mouseTransparent = false;
			enableScissorTest = false;
			// backgroundVisible = true;
			// backgroundColor = sfColor(0, 255, 255, 50);
			onMouseUp += &processMouseUp;
		}

		override vec2d world2screenPos(vec2d world)
		{
			return position + vec2d(bearingToPixel(world.x), 0);
		}

		override vec2d screen2worldPos(vec2d screen)
		{
			vec2d local = screen - position;
			return vec2d(pixelToBearing(local.x), 0);
		}

		private void processMouseUp(int x, int y, sfMouseButton btn)
		{
			if (btn == sfMouseRight)
				spawnContextMenu(x, y);
		}

		private void spawnContextMenu(int x, int y)
		{
			int xlocal = x - position.x;
			float bearing = pixelToBearing(xlocal);
			CICCreateContactFromHTrackerReq req = CICCreateContactFromHTrackerReq(
				'S', m_hydrophoneIdx, bearing);
			Button[] buttons = [
					builder(new Button()).fontSize(15).content("new tracker").build()
			];
			buttons[0].onClick += () {
				Game.ciccon.sendMessage(cast(immutable) req);
			};
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
		}

		void updatePeaks(float[] peaks)
		{
			if (m_peaks.length > peaks.length)
			{
				for (int i = m_peaks.length.to!int; i > peaks.length; i--)
					m_peaks[i - 1].drop();
				m_peaks.length = peaks.length;
			}
			else if (m_peaks.length < peaks.length)
			{
				int missing = (peaks.length - m_peaks.length).to!int;
				m_peaks.length = peaks.length;
				for (int i = 0; i < missing; i++)
					m_peaks[$ - 1 - i] = new PeakOverlayElement(this, 0);
			}
			foreach (i, p; peaks)
				m_peaks[i].m_bearing = p;
		}
	}

	private final class PeakOverlayElement: OverlayElement
	{
		private
		{
			float m_bearing;
			LineShape m_line;
			enum sfColor PEAK_COLOR = sfColor(255, 200, 200, 120);
			enum float PEAK_HEIGHT = 14;
		}

		this(TrackerOverlay to, float bearing)
		{
			m_bearing = bearing;
			enableScissorTest = false;
			super(to);
			mouseTransparent = true;
			m_line = new LineShape(vec2d(0, m_dirHeaderHeight), vec2d(0, m_dirHeaderHeight - PEAK_HEIGHT), PEAK_COLOR, 2);
		}

		override void onPreDraw()
		{
			vec2d screenPos = owner.world2screenPos(vec2d(m_bearing, 0));
			m_line.transform.position = vec2d(
				screenPos.x - owner.position.x,
				m_dirHeaderHeight);
		}

		override void draw(Window wnd, long usecsDelta)
		{
			super.draw(wnd, usecsDelta);
			m_line.render(wnd, owner.sftransform);
		}
	}
}
