# Siren Markdown Feature Verification

This document contains examples of all supported markdown features in Siren, including standard markdown and custom extensions.

## Custom Extensions

### GitHub Alerts

> [!NOTE]
> This is a **Note** alert. useful for general information.

> [!TIP]
> This is a **Tip** alert. Helpful advice or shortcuts.

> [!IMPORTANT]
> This is an **Important** alert. Key information users should know.

> [!WARNING]
> This is a **Warning** alert. Urgent info that needs immediate attention.

> [!CAUTION]
> This is a **Caution** alert. Advises about risks or negative outcomes.

### LaTeX Math

Inline math: The mass-energy equivalence formula is $E = mc^2$.

Block math:
$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

### Highlighting

To emphasize specific text, you can use ==highlighting== like this.

### Subscript and Superscript

- H~2~O (Water)
- E = mc^2^ (Energy)
- Text with both: X^2^~i~

---

## Standard Markdown

### Typography

**Bold Text**
*Italic Text*
***Bold and Italic***
~~Strikethrough~~

### Headings

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

### Lists

#### Unordered
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2

#### Ordered
1. First item
2. Second item
   1. Subitem A
   2. Subitem B

#### Task List
- [x] Completed task
- [ ] Incomplete task

### Blockquotes

> This is a blockquote.
>
> > Nested blockquote.

### Code

Inline code: `print("Hello World")`

Code block with syntax highlighting:
```dart
void main() {
  print('Hello, Siren!');
}
```

### Tables

| Name    |  Role   | Location |
| :------ | :-----: | -------: |
| Alice   |   Dev   |       NY |
| Bob     | Design  |       LA |
| Charlie | Manager |   London |

### Links and Images

[Siren Repository](https://github.com/tkinnis/siren)

![Placeholder Image](https://placehold.co/600x200?text=Siren+Markdown)

### Horizontal Rule

---
