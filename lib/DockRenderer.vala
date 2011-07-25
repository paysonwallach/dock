//  
//  Copyright (C) 2011 Robert Dyer, Rico Tzschichholz
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Cairo;
using Gdk;
using Gtk;

using Plank.Items;
using Plank.Drawing;
using Plank.Widgets;

namespace Plank
{
	public class DockRenderer : AnimatedRenderer
	{
		DockWindow window;
		
		DockPreferences Prefs {
			get { return window.Prefs; }
		}
		
		DockThemeRenderer theme;
		
		DockSurface background_buffer;
		DockSurface main_buffer;
		DockSurface indicator_buffer;
		DockSurface urgent_indicator_buffer;
		DockSurface urgent_glow_buffer;
		
		DateTime last_hide = new DateTime.from_unix_utc (0);
		
		int UrgentHueShift {
			get { return 150; }
		}
		
		public bool Hidden { get; protected set; default = true; }
		
		public double HideOffset {
			get {
				var diff = double.min (1, new DateTime.now_utc ().difference (last_hide) / (double) (theme.HideTime * 1000));
				return Hidden ? diff : 1 - diff;
			}
		}
		
		double Opacity {
			get { return double.min (1, (1 - HideOffset) + theme.FadeOpacity); }
		}
		
		public Gdk.Rectangle CursorRegion { get; protected set; }
		public Gdk.Rectangle StaticDockRegion { get; protected set; }
		
		// used to cache various sizes calculated from the theme and preferences
		int IndicatorSize { get; set; }
		int HorizPadding  { get; set; }
		int TopPadding    { get; set; }
		int BottomPadding { get; set; }
		int ItemPadding   { get; set; }
		
		public int VisibleDockHeight { get; protected set; }
		public int DockHeight { get; protected set; }
		int DockBackgroundHeight { get; set; }
		
		void reset_caches ()
		{
			var icon_size = Prefs.IconSize;
			
			IndicatorSize = (int) (theme.IndicatorSize / 10.0 * icon_size);
			HorizPadding  = (int) (theme.HorizPadding  / 10.0 * icon_size);
			TopPadding    = (int) (theme.TopPadding    / 10.0 * icon_size);
			BottomPadding = (int) (theme.BottomPadding / 10.0 * icon_size);
			ItemPadding   = (int) (theme.ItemPadding   / 10.0 * icon_size);
			
			// height of the visible (cursor) rect of the dock
			// use a temporary to avoid (possibly) doing more than 1 notify signal
			var tmp = icon_size + 2 * (theme.get_top_offset () + theme.get_bottom_offset ());
			if (TopPadding > 0)
				tmp += TopPadding;
			if (BottomPadding > 0)
				tmp += BottomPadding;
			VisibleDockHeight = tmp;
			
			// height of the dock window
			// FIXME zoom disabled
			DockHeight = tmp + (int) (icon_size * theme.UrgentBounceHeight) /*+ (int) ((Prefs.Zoom - 1) * icon_size)*/;
			
			// height of the dock background image, as drawn
			DockBackgroundHeight = tmp;
			if (TopPadding < 0)
				DockBackgroundHeight += TopPadding;
		}
		
		public int VisibleDockWidth { get; protected set; }
		public int DockWidth { get; protected set; }
		int DockBackgroundWidth { get; set; }
		
		void reset_item_caches ()
		{
			reset_caches ();
			
			var width = (int) window.Items.Items.size * (ItemPadding + Prefs.IconSize) + 2 * HorizPadding + 4 * theme.LineWidth;
			
			// width of the dock background image, as drawn
			DockBackgroundWidth = width;
			
			// width of the visible (cursor) rect of the dock
			if (HorizPadding < 0)
				width -= 2 * HorizPadding;
			VisibleDockWidth = width;
			
			// width of the dock window
			DockWidth = width + Prefs.IconSize + ItemPadding;
			
			animated_draw ();
		}
		
		public DockRenderer (DockWindow window)
		{
			base (window);
			this.window = window;
			
			CursorRegion = Gdk.Rectangle ();
			StaticDockRegion = Gdk.Rectangle ();
			
			theme = new DockThemeRenderer ();
			theme.TopRoundness = 4;
			theme.BottomRoundness = 0;
			theme.load ("dock");
			
			Prefs.notify["IconSize"].connect (icon_size_changed);
			theme.changed.connect (theme_changed);
			items_changed ();
			
			window.notify["HoveredItem"].connect (animated_draw);
			window.Items.item_removed.connect (items_changed);
			window.Items.item_added.connect (items_changed);
			window.Items.item_state_changed.connect (items_changed);
			
			notify["Hidden"].connect (hidden_changed);
		}
		
		~DockRenderer ()
		{
			Prefs.notify["IconSize"].disconnect (icon_size_changed);
			theme.changed.disconnect (theme_changed);
			
			window.notify["HoveredItem"].disconnect (animated_draw);
			window.Items.item_removed.disconnect (items_changed);
			window.Items.item_added.disconnect (items_changed);
			window.Items.item_state_changed.disconnect (items_changed);
			
			notify["Hidden"].disconnect (hidden_changed);
		}
		
		void items_changed ()
		{
			reset_item_caches ();
			update_regions ();
		}
		
		void icon_size_changed ()
		{
			reset_caches ();
			update_regions ();
		}
		
		void theme_changed ()
		{
			reset_caches ();
			update_regions ();
			window.set_size ();
		}
		
		public void show ()
		{
			if (!Hidden)
				return;
			Hidden = false;
		}
		
		public void hide ()
		{
			if (Hidden)
				return;
			Hidden = true;
		}
		
		public void reset_buffers ()
		{
			main_buffer = null;
			background_buffer = null;
			indicator_buffer = null;
			urgent_indicator_buffer = null;
			urgent_glow_buffer = null;
			
			animated_draw ();
		}
		
		public Gdk.Rectangle cursor_region ()
		{
			CursorRegion.width = VisibleDockWidth;
			CursorRegion.height = int.max (1, (int) ((1 - HideOffset) * VisibleDockHeight));
			CursorRegion.x = (window.width_request - CursorRegion.width) / 2;
			CursorRegion.y = window.height_request - CursorRegion.height;
			
			return CursorRegion;
		}
		
		public Gdk.Rectangle static_dock_region ()
		{
			return StaticDockRegion;
		}
		
		void update_regions ()
		{
			StaticDockRegion.width = VisibleDockWidth;
			StaticDockRegion.height = VisibleDockHeight;
			StaticDockRegion.x = (window.width_request - StaticDockRegion.width) / 2;
			StaticDockRegion.y = window.height_request - StaticDockRegion.height;
		}
		
		public Gdk.Rectangle item_hover_region (DockItem item)
		{
			var rect = item_draw_region (item);
			rect.x += (window.width_request - VisibleDockWidth) / 2;
			return rect;
		}
		
		public Gdk.Rectangle item_draw_region (DockItem item)
		{
			var rect = Gdk.Rectangle ();
			
			rect.x = 2 * theme.LineWidth + (HorizPadding > 0 ? HorizPadding : 0) + item.Position * (ItemPadding + Prefs.IconSize);
			rect.y = DockHeight - VisibleDockHeight;
			rect.width = Prefs.IconSize + ItemPadding;
			rect.height = VisibleDockHeight;
			
			return rect;
		}
		
		public void draw_dock (Context cr)
		{
			if (main_buffer != null && (main_buffer.Width != VisibleDockWidth || main_buffer.Height != DockHeight))
				reset_buffers ();
			
			if (main_buffer == null)
				main_buffer = new DockSurface.with_surface (VisibleDockWidth, DockHeight, cr.get_target ());
			
			main_buffer.clear ();
			
			draw_dock_background (main_buffer);
			
			foreach (var item in window.Items.Items)
				draw_item (main_buffer, item);
			
			var x_offset = (window.width_request - main_buffer.Width) / 2;
			
			cr.set_operator (Operator.SOURCE);
			var y_offset = 0.0;
			if (theme.FadeOpacity == 1.0)
				y_offset = VisibleDockHeight * HideOffset;
			cr.set_source_surface (main_buffer.Internal, x_offset, y_offset);
			cr.paint ();
			
			if (Opacity < 1.0) {
				cr.set_source_rgba (0, 0, 0, 0);
				cr.paint_with_alpha (1 - Opacity);
			}
			
			if (HideOffset == 1) {
				if (urgent_glow_buffer == null)
					create_urgent_glow (background_buffer);
				
				foreach (var item in window.Items.Items) {
					var diff = new DateTime.now_utc ().difference (item.LastUrgent);
					
					if ((item.State & ItemState.URGENT) == ItemState.URGENT && diff < theme.GlowTime * 1000) {
						var rect = item_draw_region (item);
						cr.set_source_surface (urgent_glow_buffer.Internal,
							x_offset + rect.x + rect.width / 2.0 - urgent_glow_buffer.Width / 2.0,
							DockHeight - urgent_glow_buffer.Height / 2.0);
						var opacity = 0.2 + (0.75 * (Math.sin (diff / (double) (theme.GlowPulseTime * 1000) * 2 * Math.PI) + 1) / 2);
						cr.paint_with_alpha (opacity);
					}
				}
			}
		}
		
		void draw_dock_background (DockSurface surface)
		{
			if (background_buffer == null || background_buffer.Width != DockBackgroundWidth || background_buffer.Height != DockBackgroundHeight) {
				background_buffer = new DockSurface.with_dock_surface (DockBackgroundWidth, DockBackgroundHeight, surface);
				theme.draw_background (background_buffer);
			}
			
			surface.Context.set_source_surface (background_buffer.Internal, (surface.Width - background_buffer.Width) / 2.0, surface.Height - background_buffer.Height);
			surface.Context.paint ();
		}
		
		void draw_item (DockSurface surface, DockItem item)
		{
			var icon_surface = new DockSurface.with_dock_surface (Prefs.IconSize, Prefs.IconSize, surface);
			
			// load the icon
			var item_surface = item.get_surface (icon_surface);
			icon_surface.Context.set_source_surface (item_surface.Internal, 0, 0);
			icon_surface.Context.paint ();
			
			// get draw regions
			var draw_rect = item_draw_region (item);
			var hover_rect = draw_rect;
			
			draw_rect.x += ItemPadding / 2;
			draw_rect.y += 2 * theme.get_top_offset () + (TopPadding > 0 ? TopPadding : 0);
			draw_rect.height -= TopPadding;
			
			// lighten or darken the icon
			var lighten = 0.0;
			var darken = 0.0;
			
			var max_click_time = item.ClickedAnimation == ClickAnimation.BOUNCE ? theme.LaunchBounceTime : theme.ClickTime;
			max_click_time *= 1000;
			var click_time = new DateTime.now_utc ().difference (item.LastClicked);
			if (click_time < max_click_time) {
				var clickAnimationProgress = click_time / (double) max_click_time;
				
				switch (item.ClickedAnimation) {
				case ClickAnimation.BOUNCE:
					if (Gdk.Screen.get_default ().is_composited ())
						draw_rect.y -= ((int) (Math.sin (2 * Math.PI * clickAnimationProgress) * Prefs.IconSize * theme.LaunchBounceHeight)).abs ();
					break;
				case ClickAnimation.DARKEN:
					darken = double.max (0, Math.sin (Math.PI * clickAnimationProgress)) * 0.5;
					break;
				case ClickAnimation.LIGHTEN:
					lighten = double.max (0, Math.sin (Math.PI * clickAnimationProgress)) * 0.5;
					break;
				}
			}
			
			// FIXME zoom disabled
			if (window.HoveredItem == item /*&& !Prefs.zoom_enabled ()*/)
				lighten = 0.2;
			
			if (window.HoveredItem == item && window.menu_is_visible ())
				darken += 0.4;
			
			// glow the icon
			if (lighten > 0) {
				icon_surface.Context.set_operator (Cairo.Operator.ADD);
				icon_surface.Context.paint_with_alpha (lighten);
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			// draw badge text
			if (item.BadgeText != "")
				draw_badge (icon_surface, item.BadgeText);
			
			// darken the icon
			if (darken > 0) {
				icon_surface.Context.rectangle (0, 0, icon_surface.Width, icon_surface.Height);
				icon_surface.Context.set_source_rgba (0, 0, 0, darken);
				
				icon_surface.Context.set_operator (Cairo.Operator.ATOP);
				icon_surface.Context.fill ();
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			// bounce icon on urgent state
			var urgent_time = new DateTime.now_utc ().difference (item.LastUrgent);
			if (Gdk.Screen.get_default().is_composited () && (item.State & ItemState.URGENT) != 0 && urgent_time < theme.UrgentBounceTime * 1000)
				draw_rect.y -= (int) Math.fabs (Math.sin (Math.PI * urgent_time / (double) (theme.UrgentBounceTime * 1000)) * Prefs.IconSize * theme.UrgentBounceHeight);
			
			// draw active glow
			var active_time = new DateTime.now_utc ().difference (item.LastActive);
			var opacity = double.min (1, active_time / (double) (theme.ActiveTime * 1000));
			if ((item.State & ItemState.ACTIVE) == 0)
				opacity = 1 - opacity;
			theme.draw_active_glow (surface, HorizPadding, background_buffer, hover_rect, item.AverageIconColor, opacity);
			
			// draw the icon
			surface.Context.set_source_surface (icon_surface.Internal, draw_rect.x, draw_rect.y);
			surface.Context.paint ();
			
			// draw indicators
			if (item.Indicator != IndicatorState.NONE) {
				if (indicator_buffer == null)
					create_normal_indicator ();
				if (urgent_indicator_buffer == null)
					create_urgent_indicator ();
				
				var indicator = (item.State & ItemState.URGENT) != 0 ? urgent_indicator_buffer : indicator_buffer;
				
				var x = hover_rect.x + hover_rect.width / 2 - indicator.Width / 2;
				// have to do the (int) cast to avoid valac segfault (valac 0.11.4)
 				var y = DockHeight - indicator.Height / 2 - 2 * (int) theme.get_bottom_offset () - IndicatorSize / 24.0;
				
				if (item.Indicator == IndicatorState.SINGLE) {
					surface.Context.set_source_surface (indicator.Internal, x, y);
					surface.Context.paint ();
				} else {
					surface.Context.set_source_surface (indicator.Internal, x - Prefs.IconSize / 16.0, y);
					surface.Context.paint ();
					surface.Context.set_source_surface (indicator.Internal, x + Prefs.IconSize / 16.0, y);
					surface.Context.paint ();
				}
			}
		}
		
		Drawing.Color get_styled_color ()
		{
			return new Drawing.Color.from_gdk (window.get_style ().bg [StateType.SELECTED]).set_min_value (90 / (double) uint16.MAX);
		}
		
		void create_normal_indicator ()
		{
			indicator_buffer = theme.create_indicator (background_buffer, IndicatorSize, get_styled_color ().set_min_sat (0.4));
		}
		
		void create_urgent_indicator ()
		{
			urgent_indicator_buffer = theme.create_indicator (background_buffer, IndicatorSize, get_styled_color ().add_hue (UrgentHueShift).set_sat (1));
		}
		
		void create_urgent_glow (DockSurface surface)
		{
			var color = get_styled_color ().add_hue (UrgentHueShift).set_sat (1);
			
			var size = (int) (theme.GlowSize / 10.0 * Prefs.IconSize);
			urgent_glow_buffer = new DockSurface.with_dock_surface (size, size, surface);
			
			var cr = urgent_glow_buffer.Context;
			
			var x = size / 2.0;
			
			cr.move_to (x, x);
			cr.arc (x, x, size / 2, 0, Math.PI * 2);
			
			var rg = new Pattern.radial (x, x, 0, x, x, size / 2);
			rg.add_color_stop_rgba (0, 1, 1, 1, 1);
			rg.add_color_stop_rgba (0.33, color.R, color.G, color.B, 0.66);
			rg.add_color_stop_rgba (0.66, color.R, color.G, color.B, 0.33);
			rg.add_color_stop_rgba (1.0, color.R, color.G, color.B, 0.0);
			
			cr.set_source (rg);
			cr.fill ();
		}
		
		public void draw_badge (DockSurface surface, string badge_text)
		{
			var theme_color = new Drawing.Color.from_gdk (window.get_style ().bg [StateType.SELECTED]);
			var badge_color_start = theme_color.set_val (1).set_sat (0.47);
			var badge_color_end = theme_color.set_val (0.5).set_sat (0.51);
			
			var is_small = Prefs.IconSize < 32;
			var padding = 4;
			var lineWidth = 2;
			var size = (is_small ? 0.9 : 0.65) * double.min (surface.Width, surface.Height);
			var x = surface.Width - size / 2.0;
			var y = size / 2.0;
			
			if (!is_small) {
				// draw outline shadow
				surface.Context.set_line_width (lineWidth);
				surface.Context.set_source_rgba (0, 0, 0, 0.5);
				surface.Context.arc (x, y + 1, size / 2 - lineWidth, 0, Math.PI * 2);
				surface.Context.stroke ();
				
				// draw filled gradient
				var rg = new Pattern.radial (x, lineWidth, 0, x, lineWidth, size);
				rg.add_color_stop_rgba (0, badge_color_start.R, badge_color_start.G, badge_color_start.B, badge_color_start.A);
				rg.add_color_stop_rgba (1.0, badge_color_end.R, badge_color_end.G, badge_color_end.B, badge_color_end.A);
				
				surface.Context.set_source (rg);
				surface.Context.arc (x, y, size / 2 - lineWidth, 0, Math.PI * 2);
				surface.Context.fill ();
				
				// draw outline
				surface.Context.set_source_rgba (1, 1, 1, 1);
				surface.Context.arc (x, y, size / 2 - lineWidth, 0, Math.PI * 2);
				surface.Context.stroke ();
				
				surface.Context.set_line_width (lineWidth / 2);
				surface.Context.set_source_rgba (badge_color_end.R, badge_color_end.G, badge_color_end.B, badge_color_end.A);
				surface.Context.arc (x, y, size / 2 - 2 * lineWidth, 0, Math.PI * 2);
				surface.Context.stroke ();
				
				surface.Context.set_source_rgba (0, 0, 0, 0.2);
			} else {
				lineWidth = 0;
				padding = 2;
			}
			
			var layout = new Pango.Layout (pango_context_get ());
			layout.set_width ((int) (surface.Height / 2 * Pango.SCALE));
			layout.set_ellipsize (Pango.EllipsizeMode.NONE);
			
			var font_description = new Gtk.Style ().font_desc;
			font_description.set_absolute_size ((int) (surface.Height / 2 * Pango.SCALE));
			font_description.set_weight (Pango.Weight.BOLD);
			layout.set_font_description (font_description);
			
			layout.set_text (badge_text, -1);
			Pango.Rectangle ink_rect, logical_rect;
			layout.get_pixel_extents (out ink_rect, out logical_rect);
			
			size -= 2 * padding + 2 * lineWidth;
			
			var scale = double.min (1, double.min (size / (double) logical_rect.width, size / (double) logical_rect.height));
			
			if (!is_small) {
				surface.Context.set_source_rgba (0, 0, 0, 0.2);
			} else {
				surface.Context.set_source_rgba (0, 0, 0, 0.6);
				x = surface.Width - scale * logical_rect.width / 2;
				y = scale * logical_rect.height / 2;
			}
			
			surface.Context.move_to (x - scale * logical_rect.width / 2, y - scale * logical_rect.height / 2);
			
			// draw text
			surface.Context.save ();
			if (scale < 1)
				surface.Context.scale (scale, scale);
			
			surface.Context.set_line_width (2);
			Pango.cairo_layout_path (surface.Context, layout);
			surface.Context.stroke_preserve ();
			surface.Context.set_source_rgba (1, 1, 1, 1);
			surface.Context.fill ();
			surface.Context.restore ();
		}
		
		void hidden_changed ()
		{
			var now = new DateTime.now_utc ();
			var diff = now.difference (last_hide);
			
			if (diff < theme.HideTime * 1000)
				last_hide = now.add_seconds ((diff - theme.HideTime * 1000) / 1000000.0);
			else
				last_hide = new DateTime.now_utc ();
			
			animated_draw ();
		}
		
		protected override bool animation_needed (DateTime render_time)
		{
			if (theme.FadeOpacity == 1.0) {
				if (render_time.difference (last_hide) <= theme.HideTime * 1000)
					return true;
			} else {
				if (render_time.difference (last_hide) <= theme.FadeTime * 1000)
					return true;
			}
			
			foreach (DockItem item in window.Items.Items) {
				if (render_time.difference (item.LastClicked) <= (item.ClickedAnimation == ClickAnimation.BOUNCE ? theme.LaunchBounceTime : theme.ClickTime) * 1000)
					return true;
				if (render_time.difference (item.LastActive) <= theme.ActiveTime * 1000)
					return true;
				if (render_time.difference (item.LastUrgent) <= (HideOffset == 1.0 ? theme.GlowTime : theme.UrgentBounceTime) * 1000)
					return true;
			}
				
			return false;
		}
	}
}