# Native, dependency-free WinForms drawing primitives for Windows PowerShell 5.1.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('CampusNetwork.UI.RoundedPanel' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace CampusNetwork.UI {
    // WinForms can leave ShowFocusCues/default-button emphasis enabled after a
    // mouse click. Track the actual input method so only keyboard navigation
    // draws focus outlines. The filter holds no controls and lives once per UI thread.
    internal sealed class KeyboardFocusTracker : IMessageFilter {
        [ThreadStatic] private static KeyboardFocusTracker current;
        private bool keyboardNavigation;
        internal static bool Visible {
            get { EnsureInstalled(); return current.keyboardNavigation; }
        }
        internal static void EnsureInstalled() {
            if (current == null) {
                current = new KeyboardFocusTracker();
                Application.AddMessageFilter(current);
            }
        }
        public bool PreFilterMessage(ref Message message) {
            bool next = keyboardNavigation;
            if (message.Msg == 0x0100 || message.Msg == 0x0104) {
                Keys key = (Keys)(message.WParam.ToInt64() & 0xffff);
                if (message.Msg == 0x0104 || key == Keys.Tab || key == Keys.Left || key == Keys.Right ||
                    key == Keys.Up || key == Keys.Down || key == Keys.Home || key == Keys.End ||
                    key == Keys.Space || key == Keys.Enter) { next = true; }
            } else if (message.Msg == 0x0201 || message.Msg == 0x0204 || message.Msg == 0x0207 || message.Msg == 0x020B) {
                next = false;
            }
            if (next != keyboardNavigation) {
                keyboardNavigation = next;
                Control control = Control.FromHandle(message.HWnd);
                if (control != null && control.TopLevelControl != null) { control.TopLevelControl.Invalidate(true); }
            }
            return false;
        }
    }

    internal static class DrawingTools {
        internal static GraphicsPath Rounded(RectangleF rectangle, float radius) {
            GraphicsPath path = new GraphicsPath();
            float diameter = Math.Max(0, Math.Min(radius * 2, Math.Min(rectangle.Width, rectangle.Height)));
            if (diameter < 1) { path.AddRectangle(rectangle); path.CloseFigure(); return path; }
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
        internal static Color Mix(Color first, Color second, float amount) {
            amount = Math.Max(0, Math.Min(1, amount));
            return Color.FromArgb((int)(first.A + (second.A - first.A) * amount),
                (int)(first.R + (second.R - first.R) * amount),
                (int)(first.G + (second.G - first.G) * amount),
                (int)(first.B + (second.B - first.B) * amount));
        }
        internal static Color ParentColor(Control control) {
            for (Control parent = control.Parent; parent != null; parent = parent.Parent) {
                if (parent.BackColor.A == 255) { return parent.BackColor; }
            }
            return SystemColors.Control;
        }
        internal static void Prepare(Graphics graphics) {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.CompositingQuality = CompositingQuality.HighQuality;
        }
    }

    public class RoundedPanel : Panel {
        private int radius = 20;
        private Color borderColor = Color.FromArgb(18, 25, 42, 62);
        [DefaultValue(20)]
        public int Radius { get { return radius; } set { radius = Math.Max(0, value); Invalidate(); } }
        public Color BorderColor { get { return borderColor; } set { borderColor = value; Invalidate(); } }
        public Color FillColor { get { return BackColor; } set { BackColor = value; } }
        public RoundedPanel() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.White;
            Padding = new Padding(20);
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            // Transparent child controls replay this method using translated graphics.
            // FillRectangle respects that transform; Graphics.Clear does not.
            using (SolidBrush parent = new SolidBrush(DrawingTools.ParentColor(this))) {
                e.Graphics.FillRectangle(parent, ClientRectangle);
            }
            DrawingTools.Prepare(e.Graphics);
            float scale = e.Graphics.DpiX / 96f;
            RectangleF bounds = new RectangleF(0.5f, 0.5f, Math.Max(0, Width - 1), Math.Max(0, Height - 1));
            if (bounds.Width < 1 || bounds.Height < 1) { return; }
            using (GraphicsPath path = DrawingTools.Rounded(bounds, radius * scale)) {
                using (SolidBrush fill = new SolidBrush(BackColor)) { e.Graphics.FillPath(fill, path); }
                if (borderColor.A > 0) {
                    using (Pen border = new Pen(borderColor, Math.Max(1, scale))) { e.Graphics.DrawPath(border, path); }
                }
            }
        }
    }

    public class RoundedButton : Button {
        private int radius = 12;
        private Color accentColor = Color.FromArgb(0, 122, 255);
        private Color borderColor = Color.Transparent;
        private bool hover;
        private bool pressed;
        [DefaultValue(12)]
        public int Radius { get { return radius; } set { radius = Math.Max(0, value); Invalidate(); } }
        public Color AccentColor { get { return accentColor; } set { accentColor = value; Invalidate(); } }
        public Color DefaultColor { get { return BackColor; } set { BackColor = value; } }
        public Color BorderColor { get { return borderColor; } set { borderColor = value; Invalidate(); } }
        public RoundedButton() {
            KeyboardFocusTracker.EnsureInstalled();
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            BackColor = Color.FromArgb(0, 122, 255);
            ForeColor = Color.White;
            Cursor = Cursors.Hand;
            Size = new Size(132, 42);
            AccessibleRole = AccessibleRole.PushButton;
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            using (SolidBrush parent = new SolidBrush(DrawingTools.ParentColor(this))) { e.Graphics.FillRectangle(parent, ClientRectangle); }
        }
        protected override void OnPaint(PaintEventArgs e) {
            DrawingTools.Prepare(e.Graphics);
            float scale = e.Graphics.DpiX / 96f;
            float inset = Math.Max(1, 2 * scale);
            RectangleF bounds = new RectangleF(inset, inset, Math.Max(0, Width - inset * 2), Math.Max(0, Height - inset * 2));
            if (bounds.Width < 1 || bounds.Height < 1) { return; }
            Color fill = BackColor;
            Color text = ForeColor;
            if (!Enabled) {
                fill = DrawingTools.Mix(fill, DrawingTools.ParentColor(this), 0.68f);
                text = DrawingTools.Mix(text, DrawingTools.ParentColor(this), 0.50f);
            } else if (pressed) {
                fill = DrawingTools.Mix(fill, Color.Black, 0.12f);
            } else if (hover) {
                fill = DrawingTools.Mix(fill, accentColor, 0.12f);
                if (fill.ToArgb() == BackColor.ToArgb()) { fill = DrawingTools.Mix(fill, Color.White, 0.10f); }
            }
            using (GraphicsPath path = DrawingTools.Rounded(bounds, radius * scale)) {
                using (SolidBrush brush = new SolidBrush(fill)) { e.Graphics.FillPath(brush, path); }
                if (borderColor.A > 0) {
                    using (Pen border = new Pen(borderColor, Math.Max(1, scale))) { e.Graphics.DrawPath(border, path); }
                }
            }
            if (Enabled && Focused && KeyboardFocusTracker.Visible) {
                RectangleF focusBounds = new RectangleF(0.75f * scale, 0.75f * scale,
                    Math.Max(0, Width - 1.5f * scale), Math.Max(0, Height - 1.5f * scale));
                using (GraphicsPath focus = DrawingTools.Rounded(focusBounds, (radius + 2) * scale)) {
                    using (Pen pen = new Pen(Color.FromArgb(155, accentColor), 1.5f * scale)) {
                        e.Graphics.DrawPath(pen, focus);
                    }
                }
            }
            Rectangle textBounds = Rectangle.Round(bounds);
            textBounds = new Rectangle(textBounds.X + Padding.Left, textBounds.Y + Padding.Top,
                Math.Max(1, textBounds.Width - Padding.Horizontal), Math.Max(1, textBounds.Height - Padding.Vertical));
            if (pressed) { textBounds.Offset(0, (int)Math.Max(1, scale)); }
            TextFormatFlags flags = TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            switch (TextAlign) {
                case ContentAlignment.TopLeft: flags |= TextFormatFlags.Left | TextFormatFlags.Top; break;
                case ContentAlignment.TopCenter: flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.Top; break;
                case ContentAlignment.TopRight: flags |= TextFormatFlags.Right | TextFormatFlags.Top; break;
                case ContentAlignment.MiddleLeft: flags |= TextFormatFlags.Left | TextFormatFlags.VerticalCenter; break;
                case ContentAlignment.MiddleRight: flags |= TextFormatFlags.Right | TextFormatFlags.VerticalCenter; break;
                case ContentAlignment.BottomLeft: flags |= TextFormatFlags.Left | TextFormatFlags.Bottom; break;
                case ContentAlignment.BottomCenter: flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.Bottom; break;
                case ContentAlignment.BottomRight: flags |= TextFormatFlags.Right | TextFormatFlags.Bottom; break;
                default: flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter; break;
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, text, flags);
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { pressed = true; Invalidate(); } base.OnKeyDown(e); }
        protected override void OnKeyUp(KeyEventArgs e) { pressed = false; Invalidate(); base.OnKeyUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { pressed = false; Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnEnabledChanged(e); }
        public override void NotifyDefault(bool value) { base.NotifyDefault(value); Invalidate(); }
    }

    public class ToggleSwitch : CheckBox {
        private Color accentColor = Color.FromArgb(52, 199, 89);
        private float position;
        private float target;
        private bool hover;
        private readonly Timer animation;
        public Color AccentColor { get { return accentColor; } set { accentColor = value; Invalidate(); } }
        public ToggleSwitch() {
            KeyboardFocusTracker.EnsureInstalled();
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor, true);
            AutoSize = false;
            Size = new Size(52, 30);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            AccessibleRole = AccessibleRole.CheckButton;
            animation = new Timer();
            animation.Interval = 15;
            animation.Tick += Animate;
        }
        private void Animate(object sender, EventArgs e) {
            position += (target - position) * 0.32f;
            if (Math.Abs(target - position) < 0.01f) { position = target; animation.Stop(); }
            Invalidate();
        }
        protected override void OnCheckedChanged(EventArgs e) {
            target = Checked ? 1f : 0f;
            if (IsHandleCreated && Visible && animation != null) { animation.Start(); }
            else { position = target; }
            Invalidate();
            base.OnCheckedChanged(e);
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            using (SolidBrush parent = new SolidBrush(DrawingTools.ParentColor(this))) { e.Graphics.FillRectangle(parent, ClientRectangle); }
        }
        protected override void OnPaint(PaintEventArgs e) {
            DrawingTools.Prepare(e.Graphics);
            float scale = e.Graphics.DpiX / 96f;
            float inset = 2 * scale;
            float trackHeight = Math.Max(1, Math.Min(Height - inset * 2, 28 * scale));
            float trackWidth = Math.Max(1, Math.Min(Width - inset * 2, trackHeight * 1.76f));
            RectangleF track = new RectangleF((Width - trackWidth) / 2, (Height - trackHeight) / 2, trackWidth, trackHeight);
            Color off = hover ? Color.FromArgb(216, 218, 222) : Color.FromArgb(229, 229, 234);
            Color fill = DrawingTools.Mix(off, accentColor, position);
            if (!Enabled) { fill = DrawingTools.Mix(fill, DrawingTools.ParentColor(this), 0.58f); }
            using (GraphicsPath path = DrawingTools.Rounded(track, trackHeight / 2)) {
                using (SolidBrush brush = new SolidBrush(fill)) { e.Graphics.FillPath(brush, path); }
            }
            float thumbPadding = 2 * scale;
            float thumbSize = Math.Max(1, trackHeight - thumbPadding * 2);
            float left = track.Left + thumbPadding + position * (trackWidth - thumbSize - thumbPadding * 2);
            RectangleF thumb = new RectangleF(left, track.Top + thumbPadding, thumbSize, thumbSize);
            RectangleF shadow = thumb;
            shadow.Offset(0, 1 * scale);
            using (SolidBrush shadowBrush = new SolidBrush(Color.FromArgb(25, 0, 0, 0))) { e.Graphics.FillEllipse(shadowBrush, shadow); }
            using (SolidBrush thumbBrush = new SolidBrush(Enabled ? Color.White : Color.FromArgb(247, 247, 249))) { e.Graphics.FillEllipse(thumbBrush, thumb); }
            if (Focused && KeyboardFocusTracker.Visible && Enabled) {
                RectangleF focusBounds = track;
                focusBounds.Inflate(1.5f * scale, 1.5f * scale);
                using (GraphicsPath focusPath = DrawingTools.Rounded(focusBounds, focusBounds.Height / 2)) {
                    using (Pen focusPen = new Pen(Color.FromArgb(145, accentColor), 1.3f * scale)) { e.Graphics.DrawPath(focusPen, focusPath); }
                }
            }
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void Dispose(bool disposing) {
            if (disposing && animation != null) { animation.Stop(); animation.Tick -= Animate; animation.Dispose(); }
            base.Dispose(disposing);
        }
    }

    // The native popup and input handling remain owned by ComboBox. Only its
    // collapsed face and list-item content are painted here.
    public class RoundedComboBox : ComboBox {
        private int radius = 8;
        private Color accentColor = Color.FromArgb(0, 122, 255);
        private Color borderColor = Color.Transparent;
        [DefaultValue(8)]
        public int Radius { get { return radius; } set { radius = Math.Max(0, value); Invalidate(); } }
        public Color AccentColor { get { return accentColor; } set { accentColor = value; Invalidate(); } }
        public Color BorderColor { get { return borderColor; } set { borderColor = value; Invalidate(); } }
        public RoundedComboBox() {
            KeyboardFocusTracker.EnsureInstalled();
            DrawMode = DrawMode.OwnerDrawFixed;
            DropDownStyle = ComboBoxStyle.DropDownList;
            FlatStyle = FlatStyle.Flat;
            BackColor = Color.FromArgb(243, 243, 247);
            ForeColor = Color.FromArgb(28, 28, 30);
            ItemHeight = Math.Max(20, Font.Height + 4);
        }
        protected override void OnFontChanged(EventArgs e) {
            base.OnFontChanged(e);
            ItemHeight = Math.Max(20, Font.Height + 4);
            Invalidate();
        }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            if (e.Bounds.Width < 1 || e.Bounds.Height < 1) { return; }
            bool selected = (e.State & DrawItemState.Selected) != 0;
            Color fill = selected ? Color.FromArgb(232, 241, 255) : BackColor;
            Color text = Enabled ? ForeColor : Color.FromArgb(170, 170, 176);
            using (SolidBrush brush = new SolidBrush(fill)) { e.Graphics.FillRectangle(brush, e.Bounds); }
            string itemText = e.Index >= 0 && e.Index < Items.Count ? GetItemText(Items[e.Index]) : Text;
            Rectangle textBounds = new Rectangle(e.Bounds.Left + 10, e.Bounds.Top, Math.Max(1, e.Bounds.Width - 20), e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics, itemText, Font, textBounds, text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            base.OnDrawItem(e);
        }
        private void PaintCollapsedFace(Graphics graphics) {
            if (DropDownStyle != ComboBoxStyle.DropDownList || Width < 4 || Height < 4) { return; }
            DrawingTools.Prepare(graphics);
            float scale = graphics.DpiX / 96f;
            using (SolidBrush parent = new SolidBrush(DrawingTools.ParentColor(this))) { graphics.FillRectangle(parent, ClientRectangle); }
            RectangleF bounds = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
            using (GraphicsPath path = DrawingTools.Rounded(bounds, radius * scale)) {
                using (SolidBrush fill = new SolidBrush(BackColor)) { graphics.FillPath(fill, path); }
                Color outline = Focused && KeyboardFocusTracker.Visible && Enabled ? Color.FromArgb(120, accentColor) : borderColor;
                if (outline.A > 0) { using (Pen border = new Pen(outline, Math.Max(1, scale))) { graphics.DrawPath(border, path); } }
            }
            Color textColor = Enabled ? ForeColor : Color.FromArgb(170, 170, 176);
            int left = (int)(4 * scale);
            int arrowWidth = (int)(24 * scale);
            Rectangle textBounds = new Rectangle(left, 0, Math.Max(1, Width - arrowWidth - left), Height);
            string selectedText = SelectedIndex >= 0 ? GetItemText(SelectedItem) : Text;
            TextRenderer.DrawText(graphics, selectedText, Font, textBounds, textColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            float arrowX = Width - 12 * scale;
            float arrowY = Height / 2f - 1.5f * scale;
            using (Pen arrow = new Pen(Enabled ? Color.FromArgb(142,142,147) : Color.FromArgb(199,199,204), 1.5f * scale)) {
                arrow.StartCap = LineCap.Round; arrow.EndCap = LineCap.Round; arrow.LineJoin = LineJoin.Round;
                graphics.DrawLines(arrow, new PointF[] { new PointF(arrowX - 3 * scale, arrowY),
                    new PointF(arrowX, arrowY + 3 * scale), new PointF(arrowX + 3 * scale, arrowY) });
            }
        }
        protected override void WndProc(ref Message message) {
            base.WndProc(ref message);
            if (IsDisposed || Disposing) { return; }
            if (message.Msg == 0x000F) {
                using (Graphics graphics = Graphics.FromHwnd(Handle)) { PaintCollapsedFace(graphics); }
            } else if ((message.Msg == 0x0318 || message.Msg == 0x0317) && message.WParam != IntPtr.Zero) {
                using (Graphics graphics = Graphics.FromHdc(message.WParam)) { PaintCollapsedFace(graphics); }
            }
        }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
        protected override void OnSelectedIndexChanged(EventArgs e) { base.OnSelectedIndexChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    }

    public class StatusGlyph : Control {
        private string kind = "Wifi";
        private Color accentColor = Color.FromArgb(0, 122, 255);
        private float lineWidth = 1.8f;
        [DefaultValue("Wifi")]
        public string Kind { get { return kind; } set { kind = value ?? "Wifi"; Invalidate(); } }
        public Color AccentColor { get { return accentColor; } set { accentColor = value; Invalidate(); } }
        [DefaultValue(1.8f)]
        public float LineWidth { get { return lineWidth; } set { lineWidth = Math.Max(0.7f, Math.Min(4, value)); Invalidate(); } }
        public StatusGlyph() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Size = new Size(24, 24);
            AccessibleRole = AccessibleRole.Graphic;
            TabStop = false;
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            if (BackColor.A == 0) { e.Graphics.Clear(DrawingTools.ParentColor(this)); }
            else { base.OnPaintBackground(e); }
        }
        protected override void OnPaint(PaintEventArgs e) {
            DrawingTools.Prepare(e.Graphics);
            float side = Math.Min(Width, Height);
            if (side < 2) { return; }
            GraphicsState state = e.Graphics.Save();
            try {
                e.Graphics.TranslateTransform((Width - side) / 2, (Height - side) / 2);
                e.Graphics.ScaleTransform(side / 24, side / 24);
                Color color = Enabled ? accentColor : DrawingTools.Mix(accentColor, DrawingTools.ParentColor(this), 0.55f);
                using (Pen pen = new Pen(color, lineWidth)) {
                    pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                    switch (kind.ToLowerInvariant()) {
                        case "online":
                            e.Graphics.DrawEllipse(pen, 3, 3, 18, 18);
                            e.Graphics.DrawLines(pen, new PointF[] { new PointF(7.5f,12), new PointF(10.5f,15), new PointF(16.5f,9) });
                            break;
                        case "busy":
                            e.Graphics.DrawArc(pen, 3.5f, 3.5f, 17, 17, -60, 285);
                            e.Graphics.DrawLines(pen, new PointF[] { new PointF(15.6f,3.5f), new PointF(19.6f,3.5f), new PointF(19.6f,7.5f) });
                            break;
                        case "warning":
                            e.Graphics.DrawPolygon(pen, new PointF[] { new PointF(12,3), new PointF(22,20), new PointF(2,20) });
                            e.Graphics.DrawLine(pen, 12, 9, 12, 13.5f);
                            e.Graphics.DrawLine(pen, 12, 17, 12, 17.2f);
                            break;
                        case "paused":
                            e.Graphics.DrawEllipse(pen, 3, 3, 18, 18);
                            e.Graphics.DrawLine(pen, 9.5f, 8, 9.5f, 16);
                            e.Graphics.DrawLine(pen, 14.5f, 8, 14.5f, 16);
                            break;
                        case "shield":
                            using (GraphicsPath shield = new GraphicsPath()) {
                                shield.AddLines(new PointF[] { new PointF(12,2.5f), new PointF(20,6), new PointF(19,14) });
                                shield.AddBezier(19,14,18,18,15,20,12,22);
                                shield.AddBezier(12,22,9,20,6,18,5,14);
                                shield.AddLine(5,14,4,6); shield.CloseFigure();
                                e.Graphics.DrawPath(pen, shield);
                            }
                            e.Graphics.DrawLines(pen, new PointF[] { new PointF(8.5f,12), new PointF(11,14.5f), new PointF(15.5f,9.5f) });
                            break;
                        case "pulse":
                            e.Graphics.DrawLines(pen, new PointF[] { new PointF(2,12), new PointF(6,12), new PointF(9,5), new PointF(13,19), new PointF(16,10), new PointF(18,12), new PointF(22,12) });
                            break;
                        case "settings":
                            PointF[] gear = new PointF[32];
                            for (int i = 0; i < gear.Length; i++) {
                                double angle = (i * Math.PI * 2 / gear.Length) - Math.PI / 2;
                                double radius = (i % 4 == 0 || i % 4 == 3) ? 10 : 8;
                                gear[i] = new PointF(12 + (float)(Math.Cos(angle) * radius), 12 + (float)(Math.Sin(angle) * radius));
                            }
                            e.Graphics.DrawPolygon(pen, gear);
                            e.Graphics.DrawEllipse(pen, 8.5f, 8.5f, 7, 7);
                            break;
                        case "diagnostics":
                            e.Graphics.DrawLine(pen, 5, 3, 5, 8); e.Graphics.DrawLine(pen, 5, 12, 5, 21);
                            e.Graphics.DrawLine(pen, 12, 3, 12, 13); e.Graphics.DrawLine(pen, 12, 17, 12, 21);
                            e.Graphics.DrawLine(pen, 19, 3, 19, 6); e.Graphics.DrawLine(pen, 19, 10, 19, 21);
                            e.Graphics.DrawEllipse(pen, 3, 8, 4, 4); e.Graphics.DrawEllipse(pen, 10, 13, 4, 4); e.Graphics.DrawEllipse(pen, 17, 6, 4, 4);
                            break;
                        case "logs":
                            using (GraphicsPath page = DrawingTools.Rounded(new RectangleF(5,2.5f,14,19),2)) { e.Graphics.DrawPath(pen,page); }
                            e.Graphics.DrawLine(pen, 8.5f, 8, 15.5f, 8);
                            e.Graphics.DrawLine(pen, 8.5f, 12, 15.5f, 12);
                            e.Graphics.DrawLine(pen, 8.5f, 16, 13.5f, 16);
                            break;
                        default:
                            e.Graphics.DrawArc(pen, 1.5f, 5, 21, 17, 217, 106);
                            e.Graphics.DrawArc(pen, 5, 9, 14, 12, 216, 108);
                            e.Graphics.DrawArc(pen, 8.5f, 13, 7, 7, 216, 108);
                            using (SolidBrush dot = new SolidBrush(color)) { e.Graphics.FillEllipse(dot, 10.7f, 18, 2.6f, 2.6f); }
                            break;
                    }
                }
            } finally { e.Graphics.Restore(state); }
        }
    }
}
'@
}
