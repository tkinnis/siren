# LaTeX Math Examples

A comprehensive gallery exercising **Siren**'s native pure-Dart LaTeX math engine (`tex_math_flutter` backed by `tex_math` and bundled `NewCMMath-Regular.otf`). Open this file directly in **Siren** to test inline baseline alignment, light/dark theme switching, `Cmd+=` / `Cmd+-` font scaling, `SelectionArea` copy-as-LaTeX, horizontal overflow scrolling, clickable `\href` links, and error span diagnostics.

---

## 1. Inline Baseline Alignment & Markdown Integration

### Flowing Prose

Euler's identity $e^{i\pi} + 1 = 0$ and mass-energy equivalence $E = mc^2$ sit cleanly on the text baseline alongside taller inline expressions such as $\frac{a + b}{c + d}$, radicals like $\sqrt{x^2 + y^2}$, summation $\sum_{i=1}^{n} x_i$, and integrals $\int_0^1 f(x)\,dx$.

### Heading With Inline Math $E = mc^2$ and $\alpha + \beta$

### Markdown Table Integration

| Topic | Inline Formula | Meaning |
| :--- | :--- | :--- |
| Norm | $\lVert \mathbf{v} \rVert_2 = \sqrt{\sum_{i=1}^n \lvert v_i \rvert^2}$ | Euclidean vector length |
| Conditional | $P(A \mid B) = \frac{P(A \cap B)}{P(B)}$ | Bayes conditional probability |
| Inner product | $\langle f, g \rangle = \int_a^b f(x)\,\overline{g(x)}\,dx$ | $L^2[a, b]$ inner product |

### Blockquote, List & Footnote

> For any $\sigma > 0$, the Gaussian normal density satisfies $\int_{-\infty}^{\infty} \frac{1}{\sqrt{2\pi}\sigma} e^{-\frac{(x-\mu)^2}{2\sigma^2}}\,dx = 1$.

* **Quadratic discriminant**: $\Delta = b^2 - 4ac$ determines root multiplicity.
* **Stirling's approximation**: $n! \sim \sqrt{2\pi n}\left(\frac{n}{e}\right)^n$ as $n \to \infty$.
* **Footnote formula**: The Golden Ratio $\varphi = \frac{1 + \sqrt{5}}{2}$ satisfies $\varphi^2 = \varphi + 1$[^phi].

[^phi]: Note also the continued-fraction identity $\varphi = 1 + \frac{1}{1 + \frac{1}{1 + \ddots}}$.

---

## 2. Fractions, Nested Radicals & Big Operators

### Quadratic Formula & Nested Fractions

$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}, \qquad
\sqrt{\frac{\frac{a}{b} + \frac{c}{d}}{\frac{e}{f} - \frac{g}{h}}}
$$

### Continued Fractions & Binomials

$$
\pi = 3 + \cfrac{1^2}{6 + \cfrac{3^2}{6 + \cfrac{5^2}{6 + \ddots}}}, \qquad
(x + y)^n = \sum_{k=0}^{n} \binom{n}{k} x^{n-k} y^k
$$

### Generalized Roots, Integrals & Limits

$$
\int_{-\infty}^{\infty} e^{-\alpha x^2}\,dx = \sqrt{\frac{\pi}{\alpha}}, \qquad
\oint_{\partial \Omega} \mathbf{F} \cdot d\mathbf{r} = \iint_{\Omega} (\nabla \times \mathbf{F}) \cdot d\mathbf{S}, \qquad
\lim_{n \to \infty} \left(1 + \frac{z}{n}\right)^n = e^z, \qquad
\prod_{p \text{ prime}} \frac{1}{1 - p^{-s}} = \sum_{n=1}^{\infty} \frac{1}{n^s}
$$

$$
\sqrt[n]{\frac{a_1 + a_2 + \dots + a_n}{n}} \ge \sqrt[n]{\prod_{k=1}^{n} a_k}
$$

---

## 3. Matrices, Arrays & Commutative Diagrams

### Standard & Right-Aligned Matrices (`ams` & `mathtools`)

$$
R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}, \quad
B = \begin{bmatrix} 1 & 0 & -1 \\ 0 & 2 & 4 \\ 3 & -2 & 1 \end{bmatrix}, \quad
\det \begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc, \quad
M = \begin{pmatrix*}[r] -12 & 3 \\ 4 & -5 \end{pmatrix*}
$$

Inline matrix inside text: $I_2 = \begin{smallmatrix} 1 & 0 \\ 0 & 1 \end{smallmatrix}$ keeps line height compact.

### Ruled Arrays (`array` with `\hline` & Vertical Dividers)

$$
\left(
\begin{array}{c|cc}
x & 1 & 2 \\
\hline
y & 3 & 4 \\
z & 5 & 6
\end{array}
\right)
$$

### Commutative Diagram (`amscd`)

$$
\begin{CD}
A @>f>> B \\
@VVgV @VVhV \\
C @= D
\end{CD}
$$

---

## 4. Multi-Line Alignments, Cases & Multline

### Aligned System (`align*` & `gather`)

$$
\begin{align*}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0}, & \nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t}, \\
\nabla \cdot \mathbf{B} &= 0, & \nabla \times \mathbf{B} &= \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{align*}
$$

$$
\begin{gather}
(a + b)^2 = a^2 + 2ab + b^2 \\
(a - b)^2 = a^2 - 2ab + b^2
\end{gather}
$$

### Piecewise Cases (`cases`, `dcases`, `rcases` & `empheq`)

$$
|x| = \begin{cases}
x & \text{if } x \ge 0 \\
-x & \text{if } x < 0
\end{cases}, \qquad
f(x) = \begin{dcases}
\frac{\sin x}{x} & x \neq 0 \\
1 & x = 0
\end{dcases}, \qquad
\begin{rcases}
x = r\cos\theta \\
y = r\sin\theta
\end{rcases} \implies x^2 + y^2 = r^2
$$

$$
\begin{empheq}[left=\empheqlbrack,right=\empheqrbrack]{gather}
a^2 + b^2 = c^2 \\
e^{i\pi} + 1 = 0
\end{empheq}
$$

### Staggered `multline`, `multlined` & `\shoveleft` / `\shoveright`

$$
\begin{multline} a + b + c + d \\ + e + f + g + h \\ + i + j + k + l \end{multline}
$$

$$
\begin{multlined}[t][14em]
f(x) = a_0 + a_1 x + a_2 x^2 \\
\shoveright{+ a_3 x^3 + a_4 x^4}
\end{multlined}
$$

### Equation Tags & Cross-References (`\tag`, `\label`, `\eqref`)

$$
\begin{equation}
e^{i\pi} + 1 = 0 \tag{E.1}\label{eq:euler}
\end{equation}
\qquad \text{See } \eqref{eq:euler}.
$$

---

## 5. Extensible Delimiters, Braces & Wide Accents

### Scaled Delimiters & Over/Under Braces

$$
\left\langle \frac{\int_0^1 x^2\,dx}{\sum_{k=1}^{\infty} 2^{-k}} \right\rangle, \qquad
\Bigg[ \bigg( \Big\{ \big| x \big| \Big\} \bigg) \Bigg], \qquad
\underbrace{a + b + \dots + z}_{26 \text{ terms}} + \overbrace{x_1 + \dots + x_n}^{n \text{ variables}}
$$

### Wide Accents, Brackets & Labeled Arrows

$$
\widehat{abc} + \widetilde{xyz} + \overbracket{a + b + c}^{n} + \underbracket{x + y}_{k}, \qquad
A \xrightarrow[\text{slow}]{k_1} B \xRightarrow{\text{converges}} C \xrightleftharpoons[k_{-1}]{k_1} D
$$

---

## 6. User Macros & Mathematical Alphabets

### Scoped `\newcommand` and `\def`

$$
\newcommand{\R}{\mathbb{R}}
\def\norm#1{\left\lVert #1 \right\rVert}
T : \R^n \to \R^m, \qquad \norm{T(\mathbf{x})} \le C \norm{\mathbf{x}}
$$

### Alphabets, Bold Symbols, Upright Greek & Text

$$
\mathbb{N} \subset \mathbb{Z} \subset \mathbb{Q} \subset \mathbb{R} \subset \mathbb{C}, \qquad
\mathcal{L}(\mathcal{H}), \quad \mathfrak{g}, \quad \mathscr{F}, \qquad
\boldsymbol{\alpha} + \boldsymbol{\Sigma}, \quad \upalpha + \upbeta = \uppi
$$

$$
\text{Velocity } v = \textbf{const}, \quad \textit{momentum } p = mv, \quad \texttt{complexity} = \mathcal{O}(n \log n)
$$

---

## 7. Chemistry (`mhchem`), Physics, Units & Proof Trees

### Chemical Equations, Isotopes & Physical Units (`mhchem`)

$$
\ce{N2 + 3H2 <=> 2NH3}, \qquad
\ce{CO2 + C -> 2CO}, \qquad
\ce{^{227}_{90}Th+}, \qquad
\ce{CH3-CH=CH2}, \qquad
\pu{9.81 m/s^2}
$$

### Dirac Notation, Derivatives & Physical Units (`\require{physics}`, `\require{units}`)

$$
\require{physics}
\dv{f}{x} + \pdv[2]{u}{t}, \qquad
\langle \psi \vert \hat{H} \vert \phi \rangle = \bra{\psi}\ket{\phi}, \qquad
\mqty(1 & 0 \\ 0 & 1)
$$

$$
\require{units}
g = \units[9.81]{m/s^2}, \qquad \rho = \nicefrac{3}{4}\,\units{g/cm^3}
$$

### Natural Deduction Proof Tree (`bussproofs`)

$$
\begin{prooftree}
\AxiomC{$A$}
\AxiomC{$A \to B$}
\BinaryInfC{$B$}
\end{prooftree}
$$

---

## 8. Color, Enclose, Cancel & Interactive Links (`\href`)

### Colors, Framed Boxes, Cancellations & Enclosures

$$
\color{teal}{f(x)} + \colorbox{yellow}{x^2} + \fcolorbox{red}{white}{E = mc^2} + \bbox[4px,border:2px solid #00a080]{a^2 + b^2 = c^2}
$$

$$
\frac{\cancel{(x - 1)}(x + 2)}{\cancel{(x - 1)}} = x + 2, \qquad
\bcancel{y} + \xcancel{z} + \cancelto{0}{\frac{1}{n}}, \qquad
\enclose{roundedbox}{a + b} + \enclose{circle}{r} + \enclose{updiagonalstrike}{c}
$$

### Clickable `\href` Links

Click the accent-styled links below inside **Siren** to launch them in your browser:

$$
\href{https://pub.dev/packages/tex_math_flutter}{\text{tex\_math\_flutter on pub.dev}} \qquad
\href{https://tkinnis.github.io/tex_math/}{\text{tex\_math Documentation}}
$$

---

## 9. Wide Overflow Scrolling & Error Diagnostics

### Wide Display Equation (Horizontal Scroll Test)

Resize Siren narrower or scroll horizontally across this wide equation (`TexMathOverflow.scroll`):

$$
f(x) = a_0 + a_1 x + a_2 x^2 + a_3 x^3 + a_4 x^4 + a_5 x^5 + a_6 x^6 + a_7 x^7 + a_8 x^8 + a_9 x^9 + a_{10} x^{10} + a_{11} x^{11} + a_{12} x^{12} + \sum_{k=13}^{\infty} \frac{f^{(k)}(0)}{k!} x^k
$$

### Intentional Malformed TeX (Error Widget Diagnostics)

These three formulas are intentionally invalid to demonstrate `TexMathErrorWidget` source highlighting and span reporting:

Unclosed fraction argument:

$$\frac{1}{$$

Double superscript error:

$$x^2^3$$

Unknown control sequence:

$$\unknownmacro{x}$$
