// MaxTools raster UV paketleyici.
// MaxTools.ms bu dosyayı Max içinde derler (CSharpCodeProvider). Not: kaynakta tırnaklı metin kullanılmaz.
// Adalar gerçek şekilleriyle (üçgenleri) piksel ızgarasına çizilir, boşluk kadar genişletilir ve
// en alt-sol uygun yere yerleştirilir. Böylece küçük adalar büyüklerin boşluklarına da girebilir.
// En büyük ölçek ikili arama ile bulunur.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

public class MTPacker
{
    class Island
    {
        public float[] P;      // üçgen köşeleri: x0,y0,x1,y1,x2,y2,...
        public double Area;    // UV alanı (ölçek 1)
        public double Base;    // en küçük alanlı dikdörtgene hizalama açısı (derece)
    }

    class Mask
    {
        public int W, H, Words;
        public ulong[][][] Sh;   // [kaydırma 0..63][satır][kelime]
        public double MinX, MinY;
    }

    class Placement
    {
        public double Ang, MinX, MinY;
        public int X, Y;
    }

    List<Island> islands = new List<Island>();

    public void Clear() { islands.Clear(); }

    public int Count() { return islands.Count; }

    public void AddIsland(string csv, double baseAngleDeg)
    {
        string[] parts = csv.Split((char)44);
        List<float> vals = new List<float>();
        foreach (string s in parts)
        {
            if (s.Length == 0) continue;
            vals.Add(float.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture));
        }
        float[] p = vals.ToArray();
        double a = 0;
        for (int t = 0; t + 5 < p.Length; t += 6)
            a += Math.Abs((p[t + 2] - p[t]) * (p[t + 5] - p[t + 1]) - (p[t + 4] - p[t]) * (p[t + 3] - p[t + 1])) * 0.5;
        Island I = new Island();
        I.P = p;
        I.Area = a;
        I.Base = baseAngleDeg;
        islands.Add(I);
    }

    static bool EdgeOk(double ax, double ay, double bx, double by, double ox, double oy, double qx, double qy)
    {
        double ex = bx - ax, ey = by - ay;
        double so = ex * (oy - ay) - ey * (ox - ax);
        double s1 = ex * (qy - ay) - ey * (qx - ax);
        double s2 = ex * (qy - ay) - ey * (qx + 1 - ax);
        double s3 = ex * (qy + 1 - ay) - ey * (qx - ax);
        double s4 = ex * (qy + 1 - ay) - ey * (qx + 1 - ax);
        if (so > 0) return !(s1 < 0 && s2 < 0 && s3 < 0 && s4 < 0);
        return !(s1 > 0 && s2 > 0 && s3 > 0 && s4 > 0);
    }

    // Üçgen ile [qx,qx+1]x[qy,qy+1] hücresi kesişiyor mu (ayırıcı eksen testi)
    static bool TriBox(double ax, double ay, double bx, double by, double cx, double cy, double qx, double qy)
    {
        double area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
        if (Math.Abs(area) < 1e-12) return true;
        return EdgeOk(ax, ay, bx, by, cx, cy, qx, qy) &&
               EdgeOk(bx, by, cx, cy, ax, ay, qx, qy) &&
               EdgeOk(cx, cy, ax, ay, bx, by, qx, qy);
    }

    Mask Build(Island I, double angDeg, double s, int R, int d)
    {
        double a = angDeg * Math.PI / 180.0, c = Math.Cos(a), sn = Math.Sin(a);
        int n = I.P.Length / 2;
        if (n < 3) return null;
        double[] X = new double[n], Y = new double[n];
        double mnx = double.MaxValue, mny = double.MaxValue, mxx = double.MinValue, mxy = double.MinValue;
        for (int i = 0; i < n; i++)
        {
            double px = I.P[2 * i], py = I.P[2 * i + 1];
            double x = (px * c - py * sn) * s * R, y = (px * sn + py * c) * s * R;
            X[i] = x; Y[i] = y;
            if (x < mnx) mnx = x; if (x > mxx) mxx = x;
            if (y < mny) mny = y; if (y > mxy) mxy = y;
        }
        int W = (int)Math.Ceiling(mxx - mnx) + 2 * d + 1;
        int H = (int)Math.Ceiling(mxy - mny) + 2 * d + 1;
        if (W > R || H > R) return null;

        bool[] g = new bool[W * H];
        for (int t = 0; t + 2 < n; t += 3)
        {
            double ax = X[t] - mnx + d, ay = Y[t] - mny + d;
            double bx = X[t + 1] - mnx + d, by = Y[t + 1] - mny + d;
            double cx = X[t + 2] - mnx + d, cy = Y[t + 2] - mny + d;
            int x0 = Math.Max(0, (int)Math.Floor(Math.Min(ax, Math.Min(bx, cx))));
            int x1 = Math.Min(W - 1, (int)Math.Floor(Math.Max(ax, Math.Max(bx, cx))));
            int y0 = Math.Max(0, (int)Math.Floor(Math.Min(ay, Math.Min(by, cy))));
            int y1 = Math.Min(H - 1, (int)Math.Floor(Math.Max(ay, Math.Max(by, cy))));
            for (int qy = y0; qy <= y1; qy++)
                for (int qx = x0; qx <= x1; qx++)
                    if (!g[qy * W + qx] && TriBox(ax, ay, bx, by, cx, cy, qx, qy)) g[qy * W + qx] = true;
        }

        // Boşluk kadar genişlet (önce yatay, sonra dikey)
        if (d > 0)
        {
            bool[] h = new bool[W * H];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    if (!g[y * W + x]) continue;
                    int a0 = Math.Max(0, x - d), a1 = Math.Min(W - 1, x + d);
                    for (int k = a0; k <= a1; k++) h[y * W + k] = true;
                }
            bool[] v = new bool[W * H];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    if (!h[y * W + x]) continue;
                    int b0 = Math.Max(0, y - d), b1 = Math.Min(H - 1, y + d);
                    for (int k = b0; k <= b1; k++) v[k * W + x] = true;
                }
            g = v;
        }

        int baseWords = (W + 63) / 64;
        ulong[][] baseRows = new ulong[H][];
        for (int y = 0; y < H; y++)
        {
            ulong[] row = new ulong[baseWords];
            for (int x = 0; x < W; x++)
                if (g[y * W + x]) row[x >> 6] |= 1UL << (x & 63);
            baseRows[y] = row;
        }

        Mask m = new Mask();
        m.W = W; m.H = H; m.MinX = mnx; m.MinY = mny;
        m.Words = baseWords + 1;
        m.Sh = new ulong[64][][];
        for (int sh = 0; sh < 64; sh++)
        {
            ulong[][] rows = new ulong[H][];
            for (int y = 0; y < H; y++)
            {
                ulong[] src = baseRows[y];
                ulong[] dst = new ulong[m.Words];
                for (int k = 0; k < baseWords; k++)
                {
                    if (sh == 0) { dst[k] |= src[k]; continue; }
                    dst[k] |= src[k] << sh;
                    dst[k + 1] |= src[k] >> (64 - sh);
                }
                rows[y] = dst;
            }
            m.Sh[sh] = rows;
        }
        return m;
    }

    static bool Fits(ulong[][] occ, Mask m, int x, int y)
    {
        ulong[][] rows = m.Sh[x & 63];
        int b = x >> 6;
        for (int r = 0; r < m.H; r++)
        {
            ulong[] o = occ[y + r];
            ulong[] mr = rows[r];
            for (int k = 0; k < m.Words; k++)
                if ((o[b + k] & mr[k]) != 0) return false;
        }
        return true;
    }

    static void Place(ulong[][] occ, Mask m, int x, int y)
    {
        ulong[][] rows = m.Sh[x & 63];
        int b = x >> 6;
        for (int r = 0; r < m.H; r++)
        {
            ulong[] o = occ[y + r];
            ulong[] mr = rows[r];
            for (int k = 0; k < m.Words; k++) o[b + k] |= mr[k];
        }
    }

    static double[] Angles(Island I, int rotMode)
    {
        if (rotMode <= 0) return new double[] { 0.0 };
        if (rotMode == 1) return new double[] { I.Base, I.Base + 90, I.Base + 180, I.Base + 270 };
        double[] a = new double[8];
        for (int k = 0; k < 8; k++) a[k] = I.Base + k * 45.0;
        return a;
    }

    Placement[] TryPack(int[] order, double s, int R, int d, int rotMode)
    {
        int words = R / 64 + 3;
        ulong[][] occ = new ulong[R][];
        for (int y = 0; y < R; y++) occ[y] = new ulong[words];
        Placement[] res = new Placement[islands.Count];

        foreach (int idx in order)
        {
            Island I = islands[idx];
            Placement best = null;
            Mask bestMask = null;
            int bestTop = int.MaxValue;
            foreach (double ang in Angles(I, rotMode))
            {
                Mask m = Build(I, ang, s, R, d);
                if (m == null) continue;
                bool found = false;
                for (int y = 0; y + m.H <= R && y + m.H < bestTop && !found; y++)
                {
                    for (int x = 0; x + m.W <= R; x++)
                    {
                        if (Fits(occ, m, x, y))
                        {
                            Placement p = new Placement();
                            p.Ang = ang; p.X = x; p.Y = y; p.MinX = m.MinX; p.MinY = m.MinY;
                            best = p; bestMask = m; bestTop = y + m.H;
                            found = true;
                            break;
                        }
                    }
                }
            }
            if (best == null) return null;
            Place(occ, bestMask, best.X, best.Y);
            res[idx] = best;
        }
        return res;
    }

    // Sonuç: ölçek,doluluk|açı,tx,ty|açı,tx,ty|...   (boşsa yerleşim bulunamadı)
    public string Pack(int texSize, double padPx, int rotMode, double startScale, int maxRes)
    {
        int n = islands.Count;
        if (n == 0) return string.Empty;
        double totalA = 0;
        foreach (Island I in islands) totalA += I.Area;
        if (totalA <= 0) return string.Empty;

        // Izgara çözünürlüğü: hücre ~ boşluğun dörtte biri (min 1 piksel); maxRes ile sınırlı
        double cellPx = Math.Max(1.0, padPx / 4.0);
        int R = (int)Math.Max(256.0, Math.Min((double)maxRes, texSize / cellPx));
        int d = padPx > 0 ? Math.Max(1, (int)Math.Ceiling(padPx / 2.0 * R / texSize)) : 0;

        // Farklı yerleştirme sıraları dene (alan, uzun kenar, yükseklik); en büyük ölçeği vereni tut
        double[] longSide = new double[n], height = new double[n];
        for (int i = 0; i < n; i++)
        {
            Mask m0 = Build(islands[i], Angles(islands[i], rotMode)[0], 1.0 / Math.Sqrt(totalA) * 0.5, 256, 0);
            longSide[i] = m0 == null ? 0 : Math.Max(m0.W, m0.H);
            height[i] = m0 == null ? 0 : m0.H;
        }
        List<int[]> orders = new List<int[]>();
        for (int o = 0; o < 3; o++)
        {
            int[] ord = new int[n];
            for (int i = 0; i < n; i++) ord[i] = i;
            if (o == 0) Array.Sort(ord, delegate (int a, int b) { return islands[b].Area.CompareTo(islands[a].Area); });
            if (o == 1) Array.Sort(ord, delegate (int a, int b) { return longSide[b].CompareTo(longSide[a]); });
            if (o == 2) Array.Sort(ord, delegate (int a, int b) { return height[b].CompareTo(height[a]); });
            orders.Add(ord);
        }

        double hiAll = Math.Sqrt(1.0 / totalA);
        double lo = 0;
        Placement[] best = null;
        for (int o = 0; o < orders.Count; o++)
        {
            int[] order = orders[o];
            double hi = hiAll;
            double olo = 0;
            if (o == 0 && startScale > 0 && startScale < hi)
            {
                Placement[] r = TryPack(order, startScale, R, d, rotMode);
                if (r != null) { olo = startScale; if (olo > lo) { lo = olo; best = r; } } else hi = startScale;
            }
            if (o > 0 && lo > 0)
            {
                // Önceki en iyiyi geçemiyorsa bu sırayı ele
                double probe = lo * 1.01;
                Placement[] r = TryPack(order, probe, R, d, rotMode);
                if (r == null) continue;
                olo = probe; lo = probe; best = r;
            }
            for (int it = 0; it < 12; it++)
            {
                double s = (olo + hi) / 2.0;
                Placement[] r = TryPack(order, s, R, d, rotMode);
                if (r != null) { olo = s; if (s > lo) { lo = s; best = r; } } else hi = s;
                if (hi - olo < hi * 0.004) break;
            }
        }
        if (best == null) return string.Empty;

        CultureInfo ci = CultureInfo.InvariantCulture;
        char sep = (char)44, bar = (char)124;
        StringBuilder sb = new StringBuilder();
        sb.Append(lo.ToString(ci)).Append(sep).Append((totalA * lo * lo).ToString(ci));
        for (int i = 0; i < n; i++)
        {
            Placement p = best[i];
            double tx = (p.X + d - p.MinX) / R;
            double ty = (p.Y + d - p.MinY) / R;
            sb.Append(bar).Append(p.Ang.ToString(ci)).Append(sep).Append(tx.ToString(ci)).Append(sep).Append(ty.ToString(ci));
        }
        return sb.ToString();
    }
}
