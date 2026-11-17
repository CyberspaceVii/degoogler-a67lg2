import android.content.Context;
import android.os.Looper;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Read-only package identity, actual APK signer and split-aware content snapshot. */
public final class PackageProbe {
    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder();
        for (byte b : bytes) result.append(String.format("%02x", b & 255));
        return result.toString();
    }
    public static void main(String[] args) {
        try {
            if (args.length != 1 || !args[0].matches("[a-zA-Z0-9_.]+"))
                throw new IllegalArgumentException("Expected a package name");
            if (Looper.getMainLooper() == null) Looper.prepareMainLooper();
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Object thread = activityThread.getMethod("systemMain").invoke(null);
            Context context = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
            PackageManager pm = context.getPackageManager();
            PackageInfo info;
            try {
                info = pm.getPackageInfo(args[0], PackageManager.GET_SIGNING_CERTIFICATES);
            } catch (PackageManager.NameNotFoundException absent) {
                System.out.println("state=absent");
                System.exit(0);
                return;
            }
            String base = info.applicationInfo.sourceDir;
            // Read the installed APK's certificates, not a replacement's advertised identity.
            PackageInfo archive = pm.getPackageArchiveInfo(base, PackageManager.GET_SIGNING_CERTIFICATES);
            if (archive == null || archive.signingInfo == null || !args[0].equals(archive.packageName))
                throw new IllegalStateException("APK identity unavailable");
            List<String> signers = new ArrayList<>();
            for (Signature signer : archive.signingInfo.getApkContentsSigners())
                signers.add(hex(MessageDigest.getInstance("SHA-256").digest(signer.toByteArray())));
            Collections.sort(signers);
            List<String> lineage = new ArrayList<>();
            if (!archive.signingInfo.hasMultipleSigners()) {
                Signature[] history = archive.signingInfo.getSigningCertificateHistory();
                if (history != null) for (Signature signer : history)
                    lineage.add(hex(MessageDigest.getInstance("SHA-256").digest(signer.toByteArray())));
            }
            Collections.sort(lineage);
            List<String> paths = new ArrayList<>();
            paths.add(base);
            if (info.applicationInfo.splitSourceDirs != null)
                Collections.addAll(paths, info.applicationInfo.splitSourceDirs);
            Collections.sort(paths);
            MessageDigest snapshot = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[65536];
            for (String path : paths) {
                if (path.indexOf('\n') >= 0 || !new File(path).isFile())
                    throw new IllegalStateException("Invalid APK path");
                snapshot.update(path.getBytes(StandardCharsets.UTF_8));
                snapshot.update((byte) 0);
                MessageDigest content = MessageDigest.getInstance("SHA-256");
                try (FileInputStream input = new FileInputStream(path)) {
                    int count;
                    while ((count = input.read(buffer)) != -1) content.update(buffer, 0, count);
                }
                snapshot.update(content.digest());
            }
            System.out.println("state=present");
            System.out.println("package=" + archive.packageName);
            System.out.println("signers=" + String.join(",", signers));
            System.out.println("lineage=" + String.join(",", lineage));
            System.out.println("base=" + base);
            System.out.println("version=" + info.getLongVersionCode());
            for (String path : paths) System.out.println("apk=" + path);
            System.out.println("fingerprint=" + hex(snapshot.digest()));
            System.exit(0);
        } catch (Throwable failure) {
            System.err.println("Package inspection failed: " + failure);
            failure.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
