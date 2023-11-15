package org.jlink.swingdemo;

import java.awt.HeadlessException;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.SwingUtilities;

public class SwingHello {

    public static String arg0;

    private static class Wiii extends JFrame {

        public Wiii() throws HeadlessException {
            this.setSize(1000, 1000);
            this.setLocationRelativeTo(null);
            this.add(new JLabel("Hello World " + arg0));
            this.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        Thread.sleep(1000);
                        SwingUtilities.invokeLater(() -> {
                            //Wiii.this.dispose();
                        });
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            }).start();
        }

        @Override
        public void setVisible(boolean b) {
            super.setVisible(b);
            System.out.println("X98 set visible " + b);
        }

        @Override
        public void dispose() {
            super.dispose();
            System.out.println("X98 disposed");
        }

    }

    public static void main(String... args) {
        arg0=args[0];
        System.out.println("arg: "+arg0);
        final Wiii w = new Wiii();
        SwingUtilities.invokeLater(() -> {
            w.setVisible(true);
        });
        SwingUtilities.invokeLater(() -> {
            w.repaint();
        });
        SwingUtilities.invokeLater(() -> {
            //w.pack();
        });

    }
}
