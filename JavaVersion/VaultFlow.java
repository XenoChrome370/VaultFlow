import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.plaf.basic.BasicTabbedPaneUI;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import javax.swing.table.TableCellRenderer;
import java.awt.*;
import java.awt.geom.Point2D;
import java.awt.datatransfer.StringSelection;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.SecureRandom;
import java.security.spec.KeySpec;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class VaultFlow {

    private static final File STORAGE_DIRECTORY = resolveStorageDirectory();
    private static final String PASSWORDS_FILE = new File(STORAGE_DIRECTORY, "javaStorage.json").getPath();
    private static final int PBKDF2_ITERATIONS = 480_000;
    private static final int KEY_LENGTH_BITS = 256;
    private static final int GCM_TAG_LENGTH_BITS = 128;
    private static final int GCM_IV_LENGTH_BYTES = 12;
    private static final int CLIPBOARD_CLEAR_SECONDS = 30;

    private static SecretKey derivedKey;
    private static byte[] vaultSalt;
    private static Map<String, ServiceData> passwordsData = new LinkedHashMap<>();
    private static String lastCopiedValue = null;
    private static javax.swing.Timer clipboardTimer;

    // --- Data Models ---
    public static class Account {
        public String id;
        public String username;
        public String password;
        public String notes;
        public String createdDate;
        public int length;

        public Account() {}

        public Account(String id, String username, String password, String notes) {
            this.id = id;
            this.username = username;
            this.password = password;
            this.notes = notes;
            this.createdDate = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            this.length = password.length();
        }
    }

    public static class ServiceData {
        public java.util.List<Account> accounts = new ArrayList<>();
    }

    // --- Custom Light Glass UI Components ---

    private static void paintSoftShadow(Graphics2D g2, int x, int y, int w, int h, int radius, int passes, int baseAlpha) {
        for (int i = passes; i >= 1; i--) {
            float t = i / (float) passes;
            int alpha = Math.max(0, (int) (baseAlpha * (1f - t) * 0.5f));
            int grow = i * 2;
            g2.setColor(new Color(30, 60, 110, alpha));
            g2.fillRoundRect(x - grow / 2, y - grow / 4 + i, w + grow, h + grow, radius + grow, radius + grow);
        }
    }

    public static class DynamicBackgroundPanel extends JPanel {
        public DynamicBackgroundPanel(LayoutManager layout) {
            super(layout);
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);

            int w = getWidth();
            int h = getHeight();
            if (w <= 0 || h <= 0) { g2.dispose(); super.paintComponent(g); return; }

            float[] fractions = {0f, 0.5f, 1f};
            Color[] colors = {
                    new Color(238, 246, 255),
                    new Color(222, 234, 250),
                    new Color(206, 221, 244)
            };
            LinearGradientPaint bg = new LinearGradientPaint(new Point2D.Float(0, 0), new Point2D.Float(w, h), fractions, colors);
            g2.setPaint(bg);
            g2.fillRect(0, 0, w, h);

            drawLiquidOrb(g2, -140, -130, 520, new Color(255, 255, 255), 150);
            drawLiquidOrb(g2, w - 300, h - 340, 620, new Color(170, 205, 255), 120);
            drawLiquidOrb(g2, w / 2 - 210, h / 2 - 150, 460, new Color(210, 228, 255), 110);
            drawLiquidOrb(g2, w - 520, -80, 340, new Color(255, 255, 255), 90);
            drawLiquidOrb(g2, 60, h - 260, 380, new Color(196, 220, 255), 100);

            g2.dispose();
            super.paintComponent(g);
        }

        private void drawLiquidOrb(Graphics2D g2, int x, int y, int diameter, Color core, int alpha) {
            Point2D center = new Point2D.Float(x + diameter / 2f, y + diameter / 2f);
            float radius = diameter / 2f;
            Color transparent = new Color(core.getRed(), core.getGreen(), core.getBlue(), 0);
            Color glow = new Color(core.getRed(), core.getGreen(), core.getBlue(), alpha);
            RadialGradientPaint paint = new RadialGradientPaint(center, radius,
                    new float[]{0f, 0.7f, 1f}, new Color[]{glow, new Color(core.getRed(), core.getGreen(), core.getBlue(), alpha / 3), transparent});
            g2.setPaint(paint);
            g2.fillOval(x, y, diameter, diameter);
        }
    }

    public static class GlassPanel extends JPanel {
        private int cornerRadius = 32;

        public GlassPanel() { setOpaque(false); }
        public GlassPanel(LayoutManager layout) { super(layout); setOpaque(false); }
        public GlassPanel(LayoutManager layout, int radius) { super(layout); setOpaque(false); this.cornerRadius = radius; }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { g2.dispose(); super.paintComponent(g); return; }

            paintSoftShadow(g2, 4, 6, width - 8, height - 8, cornerRadius, 6, 55);

            float[] fractions = {0f, 0.5f, 1f};
            Color[] glassColors = {
                    new Color(255, 255, 255, 190),
                    new Color(240, 246, 255, 150),
                    new Color(220, 234, 253, 120)
            };
            LinearGradientPaint fillGradient = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height), fractions, glassColors);
            g2.setPaint(fillGradient);
            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.92f));
            g2.fillRoundRect(0, 0, width - 1, height - 1, cornerRadius, cornerRadius);

            Shape clip = new java.awt.geom.RoundRectangle2D.Float(0, 0, width - 1, height - 1, cornerRadius, cornerRadius);
            Shape oldClip = g2.getClip();
            g2.clip(clip);
            RadialGradientPaint sheen = new RadialGradientPaint(
                    new Point2D.Float(width * 0.32f, -height * 0.15f), Math.max(width, height) * 0.75f,
                    new float[]{0f, 1f},
                    new Color[]{new Color(255, 255, 255, 175), new Color(255, 255, 255, 0)});
            g2.setPaint(sheen);
            g2.fillOval(-width / 2, -height / 2, width * 2, height);
            g2.setClip(oldClip);

            GradientPaint borderGradient = new GradientPaint(0, 0, new Color(255, 255, 255, 230), width, height, new Color(170, 200, 235, 130));
            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
            g2.setPaint(borderGradient);
            g2.setStroke(new BasicStroke(1.4f));
            g2.drawRoundRect(0, 0, width - 1, height - 1, cornerRadius, cornerRadius);

            g2.dispose();
            super.paintComponent(g);
        }
    }

    public static class GlassTextField extends JTextField {
        private int radius = 22;

        public GlassTextField(int columns) {
            super(columns);
            setOpaque(false);
            setBorder(new EmptyBorder(9, 16, 9, 16));
            setFont(new Font("SansSerif", Font.PLAIN, 13));
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            setForeground(new Color(30, 40, 60));
            setCaretColor(new Color(30, 40, 60));

            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { g2.dispose(); super.paintComponent(g); return; }
            int r = Math.min(radius, height);

            g2.setColor(new Color(20, 40, 80, 22));
            g2.fillRoundRect(0, 1, width - 1, height - 1, r, r);

            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
            LinearGradientPaint fill = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height),
                    new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 200), new Color(240, 247, 255, 170)});
            g2.setPaint(fill);
            g2.fillRoundRect(0, 0, width - 1, height - 2, r, r);

            g2.setColor(new Color(168, 195, 232, 170));
            g2.setStroke(new BasicStroke(1.2f));
            g2.drawRoundRect(0, 0, width - 1, height - 2, r, r);

            g2.dispose();
            super.paintComponent(g);
        }
    }

    public static class GlassPasswordField extends JPasswordField {
        private int radius = 22;

        public GlassPasswordField(int columns) {
            super(columns);
            setOpaque(false);
            setBorder(new EmptyBorder(9, 16, 9, 16));
            setFont(new Font("SansSerif", Font.PLAIN, 13));
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            setForeground(new Color(30, 40, 60));
            setCaretColor(new Color(30, 40, 60));

            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { g2.dispose(); super.paintComponent(g); return; }
            int r = Math.min(radius, height);

            g2.setColor(new Color(20, 40, 80, 22));
            g2.fillRoundRect(0, 1, width - 1, height - 1, r, r);

            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
            LinearGradientPaint fill = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height),
                    new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 200), new Color(240, 247, 255, 170)});
            g2.setPaint(fill);
            g2.fillRoundRect(0, 0, width - 1, height - 2, r, r);

            g2.setColor(new Color(168, 195, 232, 170));
            g2.setStroke(new BasicStroke(1.2f));
            g2.drawRoundRect(0, 0, width - 1, height - 2, r, r);

            g2.dispose();
            super.paintComponent(g);
        }
    }

    public static class GlassButton extends JButton {
        private boolean isHovered = false;
        private boolean isPressed = false;

        public GlassButton(String text) {
            this(text, false);
        }

        public GlassButton(String text, boolean compact) {
            super(text);
            setContentAreaFilled(false);
            setFocusPainted(false);
            setBorderPainted(false);
            setOpaque(false);
            setFont(new Font("SansSerif", Font.BOLD, compact ? 10 : 12));
            setCursor(new Cursor(Cursor.HAND_CURSOR));
            setBorder(new EmptyBorder(compact ? 2 : 8, compact ? 6 : 18, compact ? 2 : 8, compact ? 6 : 18));
            setPreferredSize(new Dimension(compact ? 56 : 140, compact ? 26 : 38));
            setMinimumSize(new Dimension(compact ? 50 : 110, compact ? 24 : 34));

            addMouseListener(new MouseAdapter() {
                @Override
                public void mouseEntered(MouseEvent e) { isHovered = true; repaint(); }
                @Override
                public void mouseExited(MouseEvent e) { isHovered = false; isPressed = false; repaint(); }
                @Override
                public void mousePressed(MouseEvent e) { isPressed = true; repaint(); }
                @Override
                public void mouseReleased(MouseEvent e) { isPressed = false; repaint(); }
            });
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            setForeground(new Color(28, 42, 68));

            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { g2.dispose(); super.paintComponent(g); return; }
            int r = Math.max(1, height);

            if (isHovered || isPressed) {
                paintSoftShadow(g2, 0, 2, width, height, r, 5, isPressed ? 70 : 95);
            } else {
                paintSoftShadow(g2, 0, 3, width, height, r, 3, 45);
            }

            Color topColor, midColor, bottomColor;
            if (isPressed) {
                topColor = new Color(175, 198, 230, 235);
                midColor = new Color(165, 190, 226, 240);
                bottomColor = new Color(150, 178, 218, 245);
            } else if (isHovered) {
                topColor = new Color(255, 255, 255, 255);
                midColor = new Color(232, 242, 255, 240);
                bottomColor = new Color(206, 224, 252, 230);
            } else {
                topColor = new Color(255, 255, 255, 205);
                midColor = new Color(238, 245, 255, 190);
                bottomColor = new Color(214, 227, 246, 175);
            }

            LinearGradientPaint bgGradient = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height),
                    new float[]{0f, 0.55f, 1f}, new Color[]{topColor, midColor, bottomColor});
            g2.setPaint(bgGradient);
            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.97f));
            g2.fillRoundRect(0, 0, width, height, r, r);

            Shape clip = new java.awt.geom.RoundRectangle2D.Float(0, 0, width, height, r, r);
            Shape oldClip = g2.getClip();
            g2.clip(clip);
            RadialGradientPaint sheen = new RadialGradientPaint(
                    new Point2D.Float(width * 0.3f, -height * 0.3f), Math.max(width, height) * 0.9f,
                    new float[]{0f, 1f},
                    new Color[]{new Color(255, 255, 255, isHovered ? 230 : 190), new Color(255, 255, 255, 0)});
            g2.setPaint(sheen);
            g2.fillOval(-width / 2, -height, width * 2, height * 2);
            g2.setClip(oldClip);

            g2.setPaint(new Color(255, 255, 255, isHovered ? 235 : 210));
            g2.setStroke(new BasicStroke(1.2f));
            g2.drawRoundRect(0, 0, width - 1, height - 1, r, r);

            g2.dispose();
            super.paintComponent(g);
        }
    }

    public static class GlassPasswordDisplayPanel extends JPanel {
        public GlassPasswordDisplayPanel() { setOpaque(false); }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { g2.dispose(); super.paintComponent(g); return; }
            int r = 22;

            paintSoftShadow(g2, 0, 1, width, height, r, 4, 30);

            LinearGradientPaint bgGradient = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height),
                    new float[]{0f, 1f}, new Color[]{new Color(248, 251, 255, 215), new Color(224, 235, 250, 195)});
            g2.setPaint(bgGradient);
            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
            g2.fillRoundRect(2, 2, width - 4, height - 4, r, r);

            Shape clip = new java.awt.geom.RoundRectangle2D.Float(2, 2, width - 4, height - 4, r, r);
            Shape oldClip = g2.getClip();
            g2.clip(clip);
            RadialGradientPaint sheen = new RadialGradientPaint(
                    new Point2D.Float(width * 0.3f, -height * 0.2f), Math.max(width, height) * 0.85f,
                    new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 190), new Color(255, 255, 255, 0)});
            g2.setPaint(sheen);
            g2.fillOval(-width / 2, -height / 2, width * 2, height * 2);
            g2.setClip(oldClip);

            GradientPaint borderGradient = new GradientPaint(0, 0, new Color(255, 255, 255, 230), width, height, new Color(180, 206, 240, 160));
            g2.setPaint(borderGradient);
            g2.setStroke(new BasicStroke(1.3f));
            g2.drawRoundRect(1, 1, width - 3, height - 3, r, r);

            g2.dispose();
            super.paintComponent(g);
        }
    }

    public static class GlassTextAreaPanel extends JPanel {
        private int radius = 20;

        public GlassTextAreaPanel(JTextArea textArea) {
            super(new BorderLayout());
            setOpaque(false);
            setBorder(new EmptyBorder(2, 2, 2, 2));

            textArea.setOpaque(false);
            textArea.setBorder(new EmptyBorder(8, 12, 8, 12));
            textArea.setForeground(new Color(30, 40, 60));
            textArea.setCaretColor(new Color(30, 40, 60));
            textArea.setFont(new Font("SansSerif", Font.PLAIN, 13));

            JScrollPane scrollPane = new JScrollPane(textArea);
            scrollPane.setOpaque(false);
            scrollPane.getViewport().setOpaque(false);
            scrollPane.setBorder(null);
            scrollPane.setHorizontalScrollBarPolicy(JScrollPane.HORIZONTAL_SCROLLBAR_NEVER);
            add(scrollPane, BorderLayout.CENTER);
        }

        @Override
        public void paint(Graphics g) {
            int width = getWidth();
            int height = getHeight();
            if (width <= 0 || height <= 0) { super.paint(g); return; }
            int r = Math.min(radius, Math.min(width, height));

            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            g2.setColor(new Color(20, 40, 80, 20));
            g2.fillRoundRect(0, 1, width - 1, height - 1, r, r);

            g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
            LinearGradientPaint fill = new LinearGradientPaint(
                    new Point2D.Float(0, 0), new Point2D.Float(0, height),
                    new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 200), new Color(240, 247, 255, 170)});
            g2.setPaint(fill);
            g2.fillRoundRect(0, 0, width - 1, height - 2, r, r);
            g2.dispose();

            Graphics2D gClip = (Graphics2D) g.create();
            gClip.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            gClip.clip(new java.awt.geom.RoundRectangle2D.Float(0, 0, width - 1, height - 2, r, r));
            super.paint(gClip);
            gClip.dispose();

            Graphics2D g2b = (Graphics2D) g.create();
            g2b.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            g2b.setColor(new Color(168, 195, 232, 170));
            g2b.setStroke(new BasicStroke(1.2f));
            g2b.drawRoundRect(0, 0, width - 1, height - 2, r, r);
            g2b.dispose();
        }
    }

    public static class GlassSpinner extends JPanel {
        private int value;
        private final int min, max, step;
        private final JLabel valueLabel = new JLabel();

        public GlassSpinner(int initial, int min, int max, int step) {
            super(new BorderLayout(4, 0));
            this.min = min;
            this.max = max;
            this.step = step;
            this.value = initial;
            setOpaque(false);
            setBorder(new EmptyBorder(3, 3, 3, 3));

            valueLabel.setHorizontalAlignment(SwingConstants.CENTER);
            valueLabel.setFont(new Font("SansSerif", Font.BOLD, 13));
            valueLabel.setForeground(new Color(30, 40, 60));

            StepButton btnMinus = new StepButton("\u2212");
            StepButton btnPlus = new StepButton("+");
            btnMinus.addActionListener(e -> setValue(value - step));
            btnPlus.addActionListener(e -> setValue(value + step));

            add(btnMinus, BorderLayout.WEST);
            add(valueLabel, BorderLayout.CENTER);
            add(btnPlus, BorderLayout.EAST);

            updateLabel();
            setPreferredSize(new Dimension(150, 38));
        }

        public int getValue() { return value; }

        public void setValue(int v) {
            int clamped = Math.max(min, Math.min(max, v));
            if (clamped != value) {
                value = clamped;
                updateLabel();
            }
        }

        private void updateLabel() { valueLabel.setText(String.valueOf(value)); }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            int width = getWidth();
            int height = getHeight();
            if (width > 0 && height > 0) {
                int r = Math.max(1, height);

                g2.setColor(new Color(20, 40, 80, 22));
                g2.fillRoundRect(0, 1, width - 1, height - 1, r, r);

                g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.95f));
                LinearGradientPaint fill = new LinearGradientPaint(
                        new Point2D.Float(0, 0), new Point2D.Float(0, height),
                        new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 205), new Color(240, 247, 255, 175)});
                g2.setPaint(fill);
                g2.fillRoundRect(0, 0, width - 1, height - 2, r, r);

                g2.setColor(new Color(168, 195, 232, 170));
                g2.setStroke(new BasicStroke(1.2f));
                g2.drawRoundRect(0, 0, width - 1, height - 2, r, r);
            }
            g2.dispose();
            super.paintComponent(g);
        }

        private static class StepButton extends JButton {
            private boolean isHovered = false;
            private boolean isPressed = false;

            public StepButton(String text) {
                super(text);
                setContentAreaFilled(false);
                setFocusPainted(false);
                setBorderPainted(false);
                setFont(new Font("SansSerif", Font.BOLD, 15));
                setForeground(new Color(45, 85, 155));
                setCursor(new Cursor(Cursor.HAND_CURSOR));
                setBorder(new EmptyBorder(2, 2, 2, 2));
                setPreferredSize(new Dimension(30, 30));

                addMouseListener(new MouseAdapter() {
                    @Override
                    public void mouseEntered(MouseEvent e) { isHovered = true; repaint(); }
                    @Override
                    public void mouseExited(MouseEvent e) { isHovered = false; isPressed = false; repaint(); }
                    @Override
                    public void mousePressed(MouseEvent e) { isPressed = true; repaint(); }
                    @Override
                    public void mouseReleased(MouseEvent e) { isPressed = false; repaint(); }
                });
            }

            @Override
            protected void paintComponent(Graphics g) {
                Graphics2D g2 = (Graphics2D) g.create();
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

                int w = getWidth();
                int h = getHeight();
                if (w > 0 && h > 0) {
                    int d = Math.max(1, Math.min(w, h) - 4);
                    int ox = (w - d) / 2;
                    int oy = (h - d) / 2;

                    Color top, bottom;
                    if (isPressed) {
                        top = new Color(180, 200, 230, 235);
                        bottom = new Color(150, 178, 218, 245);
                    } else if (isHovered) {
                        top = new Color(255, 255, 255, 255);
                        bottom = new Color(206, 224, 252, 235);
                    } else {
                        top = new Color(255, 255, 255, 215);
                        bottom = new Color(214, 227, 246, 185);
                    }
                    GradientPaint gp = new GradientPaint(0, oy, top, 0, oy + d, bottom);
                    g2.setPaint(gp);
                    g2.fillOval(ox, oy, d, d);

                    g2.setColor(new Color(255, 255, 255, 225));
                    g2.setStroke(new BasicStroke(1.1f));
                    g2.drawOval(ox, oy, d, d);
                }
                g2.dispose();
                super.paintComponent(g);
            }
        }
    }

    public static class LiquidTabbedPaneUI extends BasicTabbedPaneUI {
        @Override
        protected void installDefaults() {
            super.installDefaults();
            tabInsets = new Insets(12, 24, 12, 24);
            selectedTabPadInsets = new Insets(0, 0, 0, 0);
            contentBorderInsets = new Insets(18, 0, 0, 0);
        }

        protected Rectangle getTabAreaBounds(int tabPlacement) {
            Insets insets = tabPane.getInsets();
            Insets tabAreaInsets = getTabAreaInsets(tabPlacement);
            int width = tabPane.getWidth();
            int height = tabPane.getHeight();

            int x = insets.left + tabAreaInsets.left;
            int y = insets.top + tabAreaInsets.top;
            int w = width - insets.left - insets.right - tabAreaInsets.left - tabAreaInsets.right;
            int h = calculateTabAreaHeight(tabPlacement, runCount, maxTabHeight);

            return new Rectangle(x, y, Math.max(0, w), Math.max(0, h));
        }

        @Override
        protected void paintTabArea(Graphics g, int tabPlacement, int selectedIndex) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            Rectangle bounds = getTabAreaBounds(tabPlacement);
            if (bounds.width > 0 && bounds.height > 0) {
                int pillRadius = Math.max(1, bounds.height);
                paintSoftShadow(g2, bounds.x, bounds.y + 2, bounds.width, bounds.height - 4, pillRadius, 4, 30);

                g2.setColor(new Color(255, 255, 255, 130));
                g2.fillRoundRect(bounds.x, bounds.y + 2, bounds.width, bounds.height - 4, pillRadius, pillRadius);
            }

            g2.dispose();
            super.paintTabArea(g, tabPlacement, selectedIndex);
        }

        @Override
        protected void paintTabBackground(Graphics g, int tabPlacement, int tabIndex, int x, int y, int w, int h, boolean isSelected) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            if (isSelected && w > 0 && h > 0) {
                int pillRadius = h;
                LinearGradientPaint activeGradient = new LinearGradientPaint(
                        new Point2D.Float(x, y), new Point2D.Float(x, y + h),
                        new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 230), new Color(220, 232, 250, 195)});
                g2.setPaint(activeGradient);
                g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.96f));
                g2.fillRoundRect(x + 3, y + 3, w - 6, h - 6, pillRadius, pillRadius);

                Shape clip = new java.awt.geom.RoundRectangle2D.Float(x + 3, y + 3, w - 6, h - 6, pillRadius, pillRadius);
                Shape oldClip = g2.getClip();
                g2.clip(clip);
                RadialGradientPaint sheen = new RadialGradientPaint(
                        new Point2D.Float(x + w * 0.3f, y - h * 0.4f), Math.max(w, h) * 0.9f,
                        new float[]{0f, 1f}, new Color[]{new Color(255, 255, 255, 200), new Color(255, 255, 255, 0)});
                g2.setPaint(sheen);
                g2.fillOval(x - w / 2, y - h, w * 2, h * 2);
                g2.setClip(oldClip);

                g2.setPaint(new Color(255, 255, 255, 235));
                g2.setStroke(new BasicStroke(1.2f));
                g2.drawRoundRect(x + 3, y + 3, w - 7, h - 7, pillRadius, pillRadius);
            }
            g2.dispose();
        }

        @Override
        protected void paintTabBorder(Graphics g, int tabPlacement, int tabIndex, int x, int y, int w, int h, boolean isSelected) {}
        @Override
        protected void paintContentBorder(Graphics g, int tabPlacement, int selectedIndex) {}
        @Override
        protected void paintFocusIndicator(Graphics g, int tabPlacement, Rectangle[] rects, int tabIndex, Rectangle iconRect, Rectangle textRect, boolean isSelected) {}
    }

    // --- Main Entry Point ---
    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            try {
                UIManager.setLookAndFeel(UIManager.getCrossPlatformLookAndFeelClassName());
            } catch (Exception ignored) {}

            migrateLegacyVaultFileIfNeeded();
            boolean unlocked = unlockVault(PASSWORDS_FILE);
            if (!unlocked) {
                System.exit(0);
            }

            MainWindow window = new MainWindow();
            window.setVisible(true);
        });
    }

    // --- Crypto & Parsing Helpers ---
    private static File resolveStorageDirectory() {
        File cwd = new File(System.getProperty("user.dir")).getAbsoluteFile();
        File javaVersionDir = new File(cwd, "JavaVersion");

        if (cwd.getName().equals("JavaVersion") || javaVersionDir.exists()) {
            return cwd.getName().equals("JavaVersion") ? cwd : javaVersionDir;
        }

        return cwd;
    }

    private static void migrateLegacyVaultFileIfNeeded() {
        File legacyFile = new File("javaStorage.json");
        File targetFile = new File(PASSWORDS_FILE);
        if (!legacyFile.equals(targetFile) && legacyFile.exists() && !targetFile.exists()) {
            try {
                Files.copy(legacyFile.toPath(), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            } catch (Exception ignored) {
            }
        }
    }

    private static SecretKey deriveKey(char[] password, byte[] salt) throws Exception {
        SecretKeyFactory factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
        KeySpec spec = new PBEKeySpec(password, salt, PBKDF2_ITERATIONS, KEY_LENGTH_BITS);
        SecretKey tmp = factory.generateSecret(spec);
        return new SecretKeySpec(tmp.getEncoded(), "AES");
    }

    private static boolean unlockVault(String passwordsFile) {
        File file = new File(passwordsFile);
        byte[] salt = null;
        String encryptedPayload = null;

        if (file.exists()) {
            try {
                String raw = Files.readString(file.toPath());
                salt = Base64.getUrlDecoder().decode(extractJsonVal(raw, "salt"));
                encryptedPayload = extractJsonVal(raw, "vault");
            } catch (Exception ignored) {}
        }

        if (salt != null && !encryptedPayload.isEmpty()) {
            int attempts = 0;
            int maxAttempts = 3;
            String errorMsg = null;

            while (attempts < maxAttempts) {
                String pass = showPasswordDialog("Unlock VaultFlow", "Enter your master password to unlock VaultFlow.", errorMsg, false);
                if (pass == null) return false;

                try {
                    derivedKey = deriveKey(pass.toCharArray(), salt);
                    vaultSalt = salt;
                    byte[] decodedCiphertext = Base64.getUrlDecoder().decode(encryptedPayload);

                    byte[] iv = new byte[GCM_IV_LENGTH_BYTES];
                    System.arraycopy(decodedCiphertext, 0, iv, 0, iv.length);
                    byte[] cipherBytes = new byte[decodedCiphertext.length - GCM_IV_LENGTH_BYTES];
                    System.arraycopy(decodedCiphertext, GCM_IV_LENGTH_BYTES, cipherBytes, 0, cipherBytes.length);

                    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                    cipher.init(Cipher.DECRYPT_MODE, derivedKey, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv));
                    byte[] decrypted = cipher.doFinal(cipherBytes);

                    parseSimpleJson(new String(decrypted, StandardCharsets.UTF_8));
                    return true;
                } catch (Exception e) {
                    attempts++;
                    errorMsg = "Incorrect master password. " + (maxAttempts - attempts) + " attempt(s) remaining.";
                }
            }
            JOptionPane.showMessageDialog(null, "Too many failed attempts. Closing VaultFlow.", "Locked Out", JOptionPane.ERROR_MESSAGE);
            return false;
        } else {
            String pass = showPasswordDialog("Create Master Password", "Choose a master password to encrypt your vault.\nIf lost, data cannot be recovered.", null, true);
            if (pass == null) return false;

            try {
                SecureRandom random = new SecureRandom();
                vaultSalt = new byte[16];
                random.nextBytes(vaultSalt);

                derivedKey = deriveKey(pass.toCharArray(), vaultSalt);
                savePasswordsToFile();
                return true;
            } catch (Exception e) {
                JOptionPane.showMessageDialog(null, "Error creating vault: " + e.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
                return false;
            }
        }
    }

    private static void setPasswordEchoChar(JPasswordField first, JPasswordField second, boolean show) {
        char echo = show ? (char) 0 : '•';
        if (first != null) {
            first.setEchoChar(echo);
            first.repaint();
        }
        if (second != null) {
            second.setEchoChar(echo);
            second.repaint();
        }
    }

    private static String showPasswordDialog(String title, String prompt, String extraError, boolean isCreate) {
        JDialog dialog = new JDialog((Frame) null, title, true);
        dialog.setLayout(new BorderLayout());

        GlassPanel panel = new GlassPanel(new GridBagLayout(), 28);
        panel.setBorder(new EmptyBorder(25, 25, 25, 25));
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.fill = GridBagConstraints.HORIZONTAL;
        gbc.insets = new Insets(6, 6, 6, 6);

        gbc.gridx = 0; gbc.gridy = 0; gbc.gridwidth = 2;
        JLabel lblPrompt = new JLabel("<html><body style='width: 250px; text-align: center;'>" + prompt + "</body></html>");
        lblPrompt.setFont(new Font("SansSerif", Font.PLAIN, 13));
        panel.add(lblPrompt, gbc);

        if (extraError != null) {
            gbc.gridy++;
            JLabel lblErr = new JLabel(extraError, SwingConstants.CENTER);
            lblErr.setForeground(new Color(220, 50, 50));
            panel.add(lblErr, gbc);
        }

        gbc.gridy++; gbc.gridwidth = 1;
        panel.add(new JLabel("Master Password:"), gbc);

        gbc.gridx = 1;
        GlassPasswordField txtPass = new GlassPasswordField(15);
        panel.add(txtPass, gbc);

        GlassPasswordField txtConfirm = new GlassPasswordField(15);
        if (isCreate) {
            gbc.gridx = 0; gbc.gridy++;
            panel.add(new JLabel("Confirm Password:"), gbc);
            gbc.gridx = 1;
            panel.add(txtConfirm, gbc);
        }

        gbc.gridx = 0; gbc.gridy++; gbc.gridwidth = 2;
        JCheckBox cbShow = new JCheckBox("Show password");
        cbShow.setOpaque(false);
        cbShow.addActionListener(e -> setPasswordEchoChar(txtPass, txtConfirm, cbShow.isSelected()));
        panel.add(cbShow, gbc);

        gbc.gridy++;
        GlassButton btnOk = new GlassButton("Unlock / Save");
        final String[] result = new String[1];

        btnOk.addActionListener(e -> {
            String p1 = new String(txtPass.getPassword());
            if (p1.isEmpty()) {
                JOptionPane.showMessageDialog(dialog, "Please enter a password!", "Warning", JOptionPane.WARNING_MESSAGE);
                return;
            }
            if (isCreate) {
                if (p1.length() < 8) {
                    JOptionPane.showMessageDialog(dialog, "Password must be at least 8 characters.", "Warning", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                if (!p1.equals(new String(txtConfirm.getPassword()))) {
                    JOptionPane.showMessageDialog(dialog, "Passwords do not match!", "Warning", JOptionPane.WARNING_MESSAGE);
                    return;
                }
            }
            result[0] = p1;
            dialog.dispose();
        });

        panel.add(btnOk, gbc);

        dialog.add(panel);
        dialog.pack();
        dialog.setLocationRelativeTo(null);
        dialog.setVisible(true);

        return result[0];
    }

    private static String extractJsonVal(String json, String key) {
        Pattern pattern = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([^\"]+)\"");
        Matcher matcher = pattern.matcher(json);
        if (matcher.find()) {
            return matcher.group(1);
        }
        return "";
    }

    private static void parseSimpleJson(String jsonStr) {
        passwordsData.clear();
        if (jsonStr == null || jsonStr.trim().isEmpty() || jsonStr.trim().equals("{}")) {
            return;
        }

        String[] lines = jsonStr.split("\n");
        String currentService = null;
        Account currentAcc = null;

        for (String line : lines) {
            line = line.trim();
            if (line.endsWith("{") || line.endsWith("{\n")) {
                if (currentService == null && line.contains("\"")) {
                    currentService = line.replace("\"", "").replace(":", "").replace("{", "").trim();
                    passwordsData.putIfAbsent(currentService, new ServiceData());
                } else if (currentService != null) {
                    currentAcc = new Account();
                }
            } else if (line.startsWith("}") || line.startsWith("},")) {
                if (currentAcc != null && currentService != null) {
                    passwordsData.get(currentService).accounts.add(currentAcc);
                    currentAcc = null;
                } else if (currentService != null) {
                    currentService = null;
                }
            } else if (currentAcc != null && line.contains(":")) {
                String[] parts = line.split(":", 2);
                String k = parts[0].replace("\"", "").trim();
                String v = parts[1].replace("\"", "").replace(",", "").trim();
                if (k.equals("id")) currentAcc.id = v;
                else if (k.equals("username")) currentAcc.username = v;
                else if (k.equals("password")) currentAcc.password = v;
                else if (k.equals("notes")) currentAcc.notes = v;
                else if (k.equals("createdDate")) currentAcc.createdDate = v;
                else if (k.equals("length")) currentAcc.length = Integer.parseInt(v.isEmpty() ? "0" : v);
            }
        }
    }

    private static String serializeVaultToJson() {
        StringBuilder sb = new StringBuilder("{\n");
        int i = 0;
        for (Map.Entry<String, ServiceData> entry : passwordsData.entrySet()) {
            sb.append("  \"").append(entry.getKey()).append("\": {\n    \"accounts\": [\n");
            for (int j = 0; j < entry.getValue().accounts.size(); j++) {
                Account a = entry.getValue().accounts.get(j);
                sb.append("      {\n");
                sb.append("        \"id\": \"").append(a.id).append("\",\n");
                sb.append("        \"username\": \"").append(a.username).append("\",\n");
                sb.append("        \"password\": \"").append(a.password).append("\",\n");
                sb.append("        \"notes\": \"").append(a.notes).append("\",\n");
                sb.append("        \"createdDate\": \"").append(a.createdDate).append("\",\n");
                sb.append("        \"length\": ").append(a.length).append("\n");
                sb.append("      }").append(j < entry.getValue().accounts.size() - 1 ? "," : "").append("\n");
            }
            sb.append("    ]\n  }").append(i < passwordsData.size() - 1 ? "," : "").append("\n");
            i++;
        }
        sb.append("}");
        return sb.toString();
    }

    private static boolean savePasswordsToFile() {
        try {
            byte[] plaintext = serializeVaultToJson().getBytes(StandardCharsets.UTF_8);

            byte[] iv = new byte[GCM_IV_LENGTH_BYTES];
            new SecureRandom().nextBytes(iv);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, derivedKey, new GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv));
            byte[] encrypted = cipher.doFinal(plaintext);

            byte[] payload = new byte[iv.length + encrypted.length];
            System.arraycopy(iv, 0, payload, 0, iv.length);
            System.arraycopy(encrypted, 0, payload, iv.length, encrypted.length);

            String rootJson = String.format("{\n  \"salt\": \"%s\",\n  \"vault\": \"%s\"\n}",
                    Base64.getUrlEncoder().encodeToString(vaultSalt),
                    Base64.getUrlEncoder().encodeToString(payload));

            File target = new File(PASSWORDS_FILE);
            File parentDir = target.getParentFile();
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs();
            }

            File tmp = new File(PASSWORDS_FILE + ".tmp");
            File bak = new File(PASSWORDS_FILE + ".bak");

            Files.writeString(tmp.toPath(), rootJson);

            if (target.exists()) {
                Files.copy(target.toPath(), bak.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            JOptionPane.showMessageDialog(null, "Failed to save passwords: " + e.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
            return false;
        }
    }

    private static void copyToClipboard(String text) {
        StringSelection selection = new StringSelection(text);
        Toolkit.getDefaultToolkit().getSystemClipboard().setContents(selection, selection);
        lastCopiedValue = text;

        if (clipboardTimer != null && clipboardTimer.isRunning()) {
            clipboardTimer.stop();
        }
        clipboardTimer = new javax.swing.Timer(CLIPBOARD_CLEAR_SECONDS * 1000, e -> {
            try {
                String current = (String) Toolkit.getDefaultToolkit().getSystemClipboard().getData(java.awt.datatransfer.DataFlavor.stringFlavor);
                if (Objects.equals(current, lastCopiedValue)) {
                    Toolkit.getDefaultToolkit().getSystemClipboard().setContents(new StringSelection(""), null);
                }
            } catch (Exception ignored) {}
        });
        clipboardTimer.setRepeats(false);
        clipboardTimer.start();
    }

    // --- Main UI Window ---
    public static class MainWindow extends JFrame {

        private JTabbedPane tabbedPane;
        private DefaultTableModel tableModel;
        private JTable table;

        private JTextField addServiceInput = new GlassTextField(20);
        private JTextField addUsernameInput = new GlassTextField(20);
        private JPasswordField addPasswordInput = new GlassPasswordField(20);
        private JPasswordField addConfirmInput = new GlassPasswordField(20);
        private JTextArea addNotesInput = new JTextArea(3, 20);

        private JTextField genServiceInput = new GlassTextField(20);
        private JTextField genUsernameInput = new GlassTextField(20);
        private JTextArea genNotesInput = new JTextArea(2, 20);
        private GlassSpinner lengthSpinner = new GlassSpinner(16, 1, 128, 1);
        private JCheckBox lowerCb = new JCheckBox("Include lowercase letters (a-z)", true);
        private JCheckBox upperCb = new JCheckBox("Include uppercase letters (A-Z)", true);
        private JCheckBox numCb = new JCheckBox("Include numbers (0-9)", true);
        private JCheckBox symCb = new JCheckBox("Include symbols (!@#$%^&*)", true);
        private JTextField genDisplay = new JTextField();
        private GlassButton copyGenBtn = new GlassButton("Copy Password");
        private GlassButton saveGenBtn = new GlassButton("Save Password");

        private JTextField searchInput = new GlassTextField(20);

        public MainWindow() {
            setTitle("VaultFlow — Secure Password Manager");
            setSize(1100, 780);
            setMinimumSize(new Dimension(850, 650));
            setDefaultCloseOperation(EXIT_ON_CLOSE);
            setLocationRelativeTo(null);

            DynamicBackgroundPanel backgroundPanel = new DynamicBackgroundPanel(new BorderLayout(15, 15));
            backgroundPanel.setBorder(new EmptyBorder(15, 15, 15, 15));
            setContentPane(backgroundPanel);

            tabbedPane = new JTabbedPane();
            tabbedPane.setUI(new LiquidTabbedPaneUI());
            tabbedPane.setFont(new Font("SansSerif", Font.BOLD, 13));
            tabbedPane.setForeground(new Color(40, 50, 70));

            tabbedPane.addTab("  Generate Password  ", createGeneratorTab());
            tabbedPane.addTab("  Add Password  ", createAddPasswordTab());
            tabbedPane.addTab("  Manage Passwords  ", createManagerTab());

            backgroundPanel.add(tabbedPane, BorderLayout.CENTER);
            refreshPasswordList();
        }

        private JPanel createAddPasswordTab() {
            GlassPanel mainContainer = new GlassPanel(new BorderLayout(15, 15));
            mainContainer.setBorder(new EmptyBorder(25, 30, 25, 30));

            JLabel title = new JLabel("Add Existing Password", SwingConstants.LEFT);
            title.setFont(new Font("SansSerif", Font.BOLD, 20));
            title.setForeground(new Color(30, 40, 60));
            mainContainer.add(title, BorderLayout.NORTH);

            GlassPanel formPanel = new GlassPanel(new GridBagLayout(), 16);
            formPanel.setBorder(new EmptyBorder(20, 20, 20, 20));
            GridBagConstraints gbc = new GridBagConstraints();
            gbc.insets = new Insets(8, 8, 8, 8);
            gbc.fill = GridBagConstraints.HORIZONTAL;

            gbc.gridx = 0; gbc.gridy = 0;
            formPanel.add(createStyledLabel("Website / Service:"), gbc);
            gbc.gridx = 1;
            formPanel.add(addServiceInput, gbc);

            gbc.gridx = 0; gbc.gridy++;
            formPanel.add(createStyledLabel("Username / Email:"), gbc);
            gbc.gridx = 1;
            formPanel.add(addUsernameInput, gbc);

            gbc.gridx = 0; gbc.gridy++;
            formPanel.add(createStyledLabel("Password:"), gbc);
            gbc.gridx = 1;
            formPanel.add(addPasswordInput, gbc);

            gbc.gridx = 0; gbc.gridy++;
            formPanel.add(createStyledLabel("Confirm Password:"), gbc);
            gbc.gridx = 1;
            formPanel.add(addConfirmInput, gbc);

            gbc.gridx = 1; gbc.gridy++;
            JCheckBox showCb = new JCheckBox("Show password");
            showCb.setOpaque(false);
            showCb.setForeground(new Color(40, 50, 70));
            showCb.addActionListener(e -> setPasswordEchoChar(addPasswordInput, addConfirmInput, showCb.isSelected()));
            formPanel.add(showCb, gbc);

            gbc.gridx = 0; gbc.gridy++;
            formPanel.add(createStyledLabel("Notes (optional):"), gbc);
            gbc.gridx = 1;
            addNotesInput.setLineWrap(true);
            addNotesInput.setWrapStyleWord(true);
            GlassTextAreaPanel notesPanel = new GlassTextAreaPanel(addNotesInput);
            formPanel.add(notesPanel, gbc);

            mainContainer.add(formPanel, BorderLayout.CENTER);

            JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.CENTER, 8, 6));
            btnRow.setOpaque(false);

            GlassButton copyBtn = new GlassButton("Copy Password");
            GlassButton saveBtn = new GlassButton("Save Password");
            GlassButton clearBtn = new GlassButton("Clear All");

            copyBtn.addActionListener(e -> {
                String p = new String(addPasswordInput.getPassword());
                if (!p.isEmpty()) {
                    copyToClipboard(p);
                    JOptionPane.showMessageDialog(this, "Password copied to clipboard!\nAuto-clears in 30 seconds.");
                }
            });

            saveBtn.addActionListener(e -> {
                String s = addServiceInput.getText().trim();
                String u = addUsernameInput.getText().trim();
                String p = new String(addPasswordInput.getPassword()).trim();
                String c = new String(addConfirmInput.getPassword()).trim();
                String n = addNotesInput.getText().trim();

                if (p.isEmpty() || !p.equals(c) || s.isEmpty() || u.isEmpty()) {
                    JOptionPane.showMessageDialog(this, "Please verify all fields and confirm matching passwords.", "Warning", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                if (savePasswordData(s, u, p, n)) {
                    clearAddForm();
                }
            });

            clearBtn.addActionListener(e -> clearAddForm());

            btnRow.add(copyBtn); btnRow.add(saveBtn); btnRow.add(clearBtn);
            mainContainer.add(btnRow, BorderLayout.SOUTH);

            return mainContainer;
        }

        private JLabel createStyledLabel(String text) {
            JLabel lbl = new JLabel(text);
            lbl.setForeground(new Color(30, 40, 60));
            return lbl;
        }

        private void clearAddForm() {
            addServiceInput.setText("");
            addUsernameInput.setText("");
            addPasswordInput.setText("");
            addConfirmInput.setText("");
            addNotesInput.setText("");
        }

        private JPanel createGeneratorTab() {
            GlassPanel mainContainer = new GlassPanel(new BorderLayout(15, 15));
            mainContainer.setBorder(new EmptyBorder(25, 30, 25, 30));

            JLabel title = new JLabel("Password Generator", SwingConstants.LEFT);
            title.setFont(new Font("SansSerif", Font.BOLD, 20));
            title.setForeground(new Color(30, 40, 60));
            mainContainer.add(title, BorderLayout.NORTH);

            GlassPanel centerPanel = new GlassPanel(new GridBagLayout(), 16);
            centerPanel.setBorder(new EmptyBorder(15, 20, 15, 20));
            GridBagConstraints gbc = new GridBagConstraints();
            gbc.insets = new Insets(6, 6, 6, 6);
            gbc.fill = GridBagConstraints.HORIZONTAL;

            gbc.gridx = 0; gbc.gridy = 0;
            centerPanel.add(createStyledLabel("Website / Service:"), gbc);
            gbc.gridx = 1;
            centerPanel.add(genServiceInput, gbc);

            gbc.gridx = 0; gbc.gridy++;
            centerPanel.add(createStyledLabel("Username / Email:"), gbc);
            gbc.gridx = 1;
            centerPanel.add(genUsernameInput, gbc);

            gbc.gridx = 0; gbc.gridy++;
            centerPanel.add(createStyledLabel("Notes (optional):"), gbc);
            gbc.gridx = 1;
            genNotesInput.setLineWrap(true);
            genNotesInput.setWrapStyleWord(true);
            GlassTextAreaPanel genNotesPanel = new GlassTextAreaPanel(genNotesInput);
            centerPanel.add(genNotesPanel, gbc);

            gbc.gridx = 0; gbc.gridy++;
            centerPanel.add(createStyledLabel("Password Length:"), gbc);
            gbc.gridx = 1;
            centerPanel.add(lengthSpinner, gbc);

            gbc.gridx = 1; gbc.gridy++;
            Color checkColor = new Color(40, 50, 70);
            lowerCb.setOpaque(false); lowerCb.setForeground(checkColor);
            upperCb.setOpaque(false); upperCb.setForeground(checkColor);
            numCb.setOpaque(false); numCb.setForeground(checkColor);
            symCb.setOpaque(false); symCb.setForeground(checkColor);

            centerPanel.add(lowerCb, gbc); gbc.gridy++;
            centerPanel.add(upperCb, gbc); gbc.gridy++;
            centerPanel.add(numCb, gbc); gbc.gridy++;
            centerPanel.add(symCb, gbc);

            gbc.gridx = 0; gbc.gridy++; gbc.gridwidth = 2;
            GlassButton genBtn = new GlassButton("Generate Secure Password");
            genBtn.addActionListener(e -> generatePassword());
            centerPanel.add(genBtn, gbc);

            gbc.gridy++;
            gbc.insets = new Insets(14, 6, 6, 6);

            GlassPasswordDisplayPanel heroPanel = new GlassPasswordDisplayPanel();
            heroPanel.setLayout(new BorderLayout());
            heroPanel.setBorder(new EmptyBorder(12, 18, 12, 18));

            genDisplay.setFont(new Font("Monospaced", Font.BOLD, 15));
            genDisplay.setForeground(new Color(25, 45, 80));
            genDisplay.setHorizontalAlignment(JTextField.CENTER);
            genDisplay.setEditable(false);
            genDisplay.setOpaque(false);
            genDisplay.setBorder(null);
            genDisplay.setText("Select options & click generate");

            heroPanel.add(genDisplay, BorderLayout.CENTER);
            centerPanel.add(heroPanel, gbc);

            mainContainer.add(centerPanel, BorderLayout.CENTER);

            JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.CENTER, 8, 6));
            btnRow.setOpaque(false);

            copyGenBtn.setEnabled(false);
            saveGenBtn.setEnabled(false);

            copyGenBtn.addActionListener(e -> {
                copyToClipboard(genDisplay.getText());
                JOptionPane.showMessageDialog(this, "Generated password copied to clipboard!");
            });

            saveGenBtn.addActionListener(e -> {
                String s = genServiceInput.getText().trim();
                String u = genUsernameInput.getText().trim();
                String p = genDisplay.getText();
                String n = genNotesInput.getText().trim();

                if (s.isEmpty() || u.isEmpty() || p.startsWith("Select options")) {
                    JOptionPane.showMessageDialog(this, "Please enter details and generate a valid password first.", "Warning", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                if (savePasswordData(s, u, p, n)) {
                    genServiceInput.setText("");
                    genUsernameInput.setText("");
                    genNotesInput.setText("");
                    genDisplay.setText("Select options & click generate");
                    copyGenBtn.setEnabled(false);
                    saveGenBtn.setEnabled(false);
                }
            });

            GlassButton clearBtn = new GlassButton("Clear All");
            clearBtn.addActionListener(e -> {
                genServiceInput.setText("");
                genUsernameInput.setText("");
                genNotesInput.setText("");
                genDisplay.setText("Select options & click generate");
                copyGenBtn.setEnabled(false);
                saveGenBtn.setEnabled(false);
            });

            btnRow.add(copyGenBtn); btnRow.add(saveGenBtn); btnRow.add(clearBtn);
            mainContainer.add(btnRow, BorderLayout.SOUTH);

            return mainContainer;
        }

        private void generatePassword() {
            int len = lengthSpinner.getValue();
            StringBuilder chars = new StringBuilder();
            if (lowerCb.isSelected()) chars.append("abcdefghijklmnopqrstuvwxyz");
            if (upperCb.isSelected()) chars.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
            if (numCb.isSelected()) chars.append("0123456789");
            if (symCb.isSelected()) chars.append("!@#$%^&*()_+-=[]{}|;:,.<>?");

            if (chars.length() == 0) {
                JOptionPane.showMessageDialog(this, "Select at least one character set!", "Warning", JOptionPane.WARNING_MESSAGE);
                return;
            }

            SecureRandom sr = new SecureRandom();
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < len; i++) {
                sb.append(chars.charAt(sr.nextInt(chars.length())));
            }

            genDisplay.setText(sb.toString());
            copyGenBtn.setEnabled(true);
            saveGenBtn.setEnabled(true);
        }

        private JPanel createManagerTab() {
            GlassPanel mainContainer = new GlassPanel(new BorderLayout(15, 15));
            mainContainer.setBorder(new EmptyBorder(25, 25, 25, 25));

            JPanel topPanel = new JPanel(new BorderLayout(10, 10));
            topPanel.setOpaque(false);

            JLabel title = new JLabel("Saved Vault Passwords", SwingConstants.LEFT);
            title.setFont(new Font("SansSerif", Font.BOLD, 20));
            title.setForeground(new Color(30, 40, 60));
            topPanel.add(title, BorderLayout.WEST);

            JPanel searchRow = new JPanel(new FlowLayout(FlowLayout.RIGHT));
            searchRow.setOpaque(false);
            searchRow.add(createStyledLabel("Search: "));
            searchRow.add(searchInput);
            topPanel.add(searchRow, BorderLayout.EAST);

            searchInput.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
                public void insertUpdate(javax.swing.event.DocumentEvent e) { filter(); }
                public void removeUpdate(javax.swing.event.DocumentEvent e) { filter(); }
                public void changedUpdate(javax.swing.event.DocumentEvent e) { filter(); }

                private void filter() { refreshPasswordList(); }
            });

            mainContainer.add(topPanel, BorderLayout.NORTH);

            tableModel = new DefaultTableModel(new String[]{"Website/Service", "Username", "Password", "Notes", "Created Date", "Actions"}, 0) {
                @Override
                public boolean isCellEditable(int row, int column) { return column == 5; }
            };

            table = new JTable(tableModel);
            table.setRowHeight(42);
            table.setOpaque(false);
            table.setShowGrid(false);
            table.setIntercellSpacing(new Dimension(0, 0));
            table.getTableHeader().setFont(new Font("SansSerif", Font.BOLD, 12));
            table.getTableHeader().setOpaque(false);

            DefaultTableCellRenderer transparentRenderer = new DefaultTableCellRenderer();
            transparentRenderer.setOpaque(false);
            transparentRenderer.setForeground(new Color(30, 40, 60));

            for (int i = 0; i < 5; i++) {
                table.getColumnModel().getColumn(i).setCellRenderer(transparentRenderer);
            }

            table.getColumnModel().getColumn(5).setPreferredWidth(210);
            table.getColumnModel().getColumn(5).setMinWidth(200);
            table.getColumnModel().getColumn(5).setCellRenderer(new ActionPanelRenderer());
            table.getColumnModel().getColumn(5).setCellEditor(new ActionPanelEditor());

            JScrollPane pane = new JScrollPane(table);
            pane.getViewport().setOpaque(false);
            pane.setOpaque(false);
            pane.setBorder(BorderFactory.createEmptyBorder());
            mainContainer.add(pane, BorderLayout.CENTER);

            JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 6));
            btnRow.setOpaque(false);

            GlassButton refreshBtn = new GlassButton("Refresh");
            GlassButton editBtn = new GlassButton("Edit Selected");
            GlassButton deleteBtn = new GlassButton("Delete Selected");
            GlassButton exportBtn = new GlassButton("Export All");

            refreshBtn.addActionListener(e -> refreshPasswordList());
            editBtn.addActionListener(e -> editSelected());
            deleteBtn.addActionListener(e -> deleteSelected());
            exportBtn.addActionListener(e -> exportPasswords());

            btnRow.add(refreshBtn); btnRow.add(editBtn);
            btnRow.add(deleteBtn); btnRow.add(exportBtn);

            mainContainer.add(btnRow, BorderLayout.SOUTH);

            return mainContainer;
        }

        private synchronized void refreshPasswordList() {
            tableModel.setRowCount(0);
            String filterText = searchInput.getText().toLowerCase();

            for (Map.Entry<String, ServiceData> entry : passwordsData.entrySet()) {
                String service = entry.getKey();
                ServiceData sd = entry.getValue();

                boolean isFirst = true;
                for (Account acc : sd.accounts) {
                    if (!filterText.isEmpty()) {
                        boolean match = service.toLowerCase().contains(filterText) ||
                                acc.username.toLowerCase().contains(filterText) ||
                                (acc.notes != null && acc.notes.toLowerCase().contains(filterText));
                        if (!match) continue;
                    }

                    String displayService = isFirst ? service : "";
                    String hiddenPass = "•".repeat(acc.password.length());

                    tableModel.addRow(new Object[]{
                            displayService,
                            acc.username,
                            hiddenPass,
                            acc.notes,
                            acc.createdDate,
                            acc
                    });
                    isFirst = false;
                }
            }
        }

        private boolean savePasswordData(String service, String username, String password, String notes) {
            String accId = String.valueOf(System.currentTimeMillis());
            Account acc = new Account(accId, username, password, notes);

            if (!passwordsData.containsKey(service)) {
                ServiceData sd = new ServiceData();
                sd.accounts.add(acc);
                passwordsData.put(service, sd);
            } else {
                ServiceData sd = passwordsData.get(service);
                for (Account existing : sd.accounts) {
                    if (existing.username.equals(username)) {
                        int reply = JOptionPane.showConfirmDialog(this, "Username exists. Add anyway?", "Confirm", JOptionPane.YES_NO_OPTION);
                        if (reply != JOptionPane.YES_OPTION) return false;
                        break;
                    }
                }
                sd.accounts.add(acc);
            }

            if (savePasswordsToFile()) {
                refreshPasswordList();
                JOptionPane.showMessageDialog(this, "Password saved successfully!");
                return true;
            }
            return false;
        }

        private void editSelected() {
            int row = table.getSelectedRow();
            if (row < 0) {
                JOptionPane.showMessageDialog(this, "Select an entry to edit!");
                return;
            }
            Account acc = (Account) tableModel.getValueAt(row, 5);
            showEditDialog(acc);
        }

        private void showEditDialog(Account acc) {
            JDialog dialog = new JDialog(this, "Edit Account", true);
            GlassPanel panel = new GlassPanel(new GridBagLayout(), 24);
            panel.setBorder(new EmptyBorder(20, 20, 20, 20));
            GridBagConstraints gbc = new GridBagConstraints();
            gbc.insets = new Insets(6, 6, 6, 6);
            gbc.fill = GridBagConstraints.HORIZONTAL;

            JTextField txtUser = new GlassTextField(15);
            txtUser.setText(acc.username);
            JPasswordField txtPass = new GlassPasswordField(15);
            txtPass.setText(acc.password);
            JPasswordField txtConfirm = new GlassPasswordField(15);
            txtConfirm.setText(acc.password);
            JTextArea txtNotes = new JTextArea(acc.notes, 3, 15);
            txtNotes.setLineWrap(true);
            txtNotes.setWrapStyleWord(true);

            gbc.gridx = 0; gbc.gridy = 0; panel.add(createStyledLabel("Username:"), gbc);
            gbc.gridx = 1; panel.add(txtUser, gbc);
            gbc.gridx = 0; gbc.gridy++; panel.add(createStyledLabel("Password:"), gbc);
            gbc.gridx = 1; panel.add(txtPass, gbc);
            gbc.gridx = 0; gbc.gridy++; panel.add(createStyledLabel("Confirm:"), gbc);
            gbc.gridx = 1; panel.add(txtConfirm, gbc);
            gbc.gridx = 0; gbc.gridy++; panel.add(createStyledLabel("Notes:"), gbc);
            gbc.gridx = 1;
            GlassTextAreaPanel notesPanel = new GlassTextAreaPanel(txtNotes);
            panel.add(notesPanel, gbc);

            gbc.gridx = 0; gbc.gridy++; gbc.gridwidth = 2;
            GlassButton btnSave = new GlassButton("Save Changes");
            btnSave.addActionListener(e -> {
                String u = txtUser.getText().trim();
                String p = new String(txtPass.getPassword()).trim();
                String c = new String(txtConfirm.getPassword()).trim();

                if (u.isEmpty() || p.isEmpty() || !p.equals(c)) {
                    JOptionPane.showMessageDialog(dialog, "Validation failed!", "Warning", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                acc.username = u;
                acc.password = p;
                acc.notes = txtNotes.getText().trim();
                acc.length = p.length();

                savePasswordsToFile();
                refreshPasswordList();
                dialog.dispose();
            });
            panel.add(btnSave, gbc);

            dialog.add(panel);
            dialog.pack();
            dialog.setLocationRelativeTo(this);
            dialog.setVisible(true);
        }

        private void deleteSelected() {
            int row = table.getSelectedRow();
            if (row < 0) {
                JOptionPane.showMessageDialog(this, "Select an item to delete!");
                return;
            }
            Account acc = (Account) tableModel.getValueAt(row, 5);

            int confirm = JOptionPane.showConfirmDialog(this, "Delete account " + acc.username + "?", "Confirm", JOptionPane.YES_NO_OPTION);
            if (confirm == JOptionPane.YES_OPTION) {
                for (Map.Entry<String, ServiceData> entry : passwordsData.entrySet()) {
                    entry.getValue().accounts.removeIf(a -> a.id.equals(acc.id));
                }
                passwordsData.entrySet().removeIf(e -> e.getValue().accounts.isEmpty());
                savePasswordsToFile();
                refreshPasswordList();
            }
        }

        private void exportPasswords() {
            if (passwordsData.isEmpty()) {
                JOptionPane.showMessageDialog(this, "No passwords to export!");
                return;
            }

            int confirm = JOptionPane.showConfirmDialog(this, "Export plaintext passwords to clipboard?", "Warning", JOptionPane.YES_NO_OPTION);
            if (confirm != JOptionPane.YES_OPTION) return;

            StringBuilder sb = new StringBuilder("Password Export\n===================\n\n");
            for (Map.Entry<String, ServiceData> entry : passwordsData.entrySet()) {
                sb.append("Service: ").append(entry.getKey()).append("\n");
                for (Account acc : entry.getValue().accounts) {
                    sb.append("  Username: ").append(acc.username).append("\n");
                    sb.append("  Password: ").append(acc.password).append("\n");
                    sb.append("  Notes: ").append(acc.notes).append("\n\n");
                }
            }

            copyToClipboard(sb.toString());
            JOptionPane.showMessageDialog(this, "Export copied to clipboard!");
        }

        private class ActionPanel extends JPanel {
            GlassButton btnShow = new GlassButton("Show", true);
            GlassButton btnCopy = new GlassButton("Copy", true);
            GlassButton btnEdit = new GlassButton("Edit", true);

            public ActionPanel() {
                setLayout(new GridBagLayout());
                setOpaque(false);
                JPanel inner = new JPanel(new FlowLayout(FlowLayout.CENTER, 4, 0));
                inner.setOpaque(false);
                inner.add(btnShow);
                inner.add(btnCopy);
                inner.add(btnEdit);
                add(inner);
            }
        }

        private class ActionPanelRenderer implements TableCellRenderer {
            private ActionPanel panel = new ActionPanel();

            @Override
            public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int column) {
                String currentVal = (String) table.getValueAt(row, 2);
                Account acc = (Account) value;
                if (acc != null && currentVal != null && !currentVal.startsWith("•")) {
                    panel.btnShow.setText("Hide");
                } else {
                    panel.btnShow.setText("Show");
                }
                return panel;
            }
        }

        private class ActionPanelEditor extends AbstractCellEditor implements javax.swing.table.TableCellEditor {
            private ActionPanel panel = new ActionPanel();
            private int currentRow = -1;
            private Account currentAccount = null;

            public ActionPanelEditor() {
                panel.btnShow.addActionListener(e -> {
                    if (currentRow != -1 && currentAccount != null) {
                        String current = (String) table.getValueAt(currentRow, 2);
                        if (current.startsWith("•")) {
                            table.setValueAt(currentAccount.password, currentRow, 2);
                            panel.btnShow.setText("Hide");
                        } else {
                            table.setValueAt("•".repeat(currentAccount.password.length()), currentRow, 2);
                            panel.btnShow.setText("Show");
                        }
                    }
                    fireEditingStopped();
                });

                panel.btnCopy.addActionListener(e -> {
                    if (currentRow != -1 && currentAccount != null) {
                        copyToClipboard(currentAccount.password);
                        JOptionPane.showMessageDialog(MainWindow.this, "Password copied!");
                    }
                    fireEditingStopped();
                });

                panel.btnEdit.addActionListener(e -> {
                    Account accToEdit = currentAccount;
                    fireEditingStopped();
                    if (accToEdit != null) {
                        showEditDialog(accToEdit);
                    }
                });
            }

            @Override
            public Component getTableCellEditorComponent(JTable table, Object value, boolean isSelected, int row, int column) {
                this.currentRow = row;
                this.currentAccount = (Account) value;
                String currentVal = (String) table.getValueAt(row, 2);

                if (currentAccount != null && currentVal != null && !currentVal.startsWith("•")) {
                    panel.btnShow.setText("Hide");
                } else {
                    panel.btnShow.setText("Show");
                }
                return panel;
            }

            @Override
            public Object getCellEditorValue() {
                return currentAccount;
            }
        }
    }
}
