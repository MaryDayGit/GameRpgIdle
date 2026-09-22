# Сайт игры и обязательные страницы

Одна папка — один адрес. Публикуется целиком, содержимое:

| Файл | Что это |
|---|---|
| `index.html` + `sil.js`, `descent.js`, `page.js` | сайт-визитка: живое окно спуска, бестиарий, реликты, логова |
| `legal/privacy.html` | политика конфиденциальности (RU + EN) |
| `legal/delete-account.html` | удаление аккаунта и данных (RU + EN) |
| `icon-512.png`, `og-image.png` | значок вкладки и картинка для превью в мессенджерах |

Силуэты существ на сайте рисует тот же код, что и в игре (`sil.js` — порт
`app/lib/game/silhouettes.dart`), а числа взяты из `assets/content`. Правится
баланс — сайт расходится с игрой; сверять при заметных правках.

## Куда идут ссылки в Play Console

| Страница | Поле |
|---|---|
| `legal/privacy.html` | *App content → Privacy policy* |
| `legal/delete-account.html` | *App content → Data safety* → ссылка на запрос удаления |

Контакт на обеих страницах — `donut.dev.inc@gmail.com`, тот же, что указан в
Play Console. Сменится адрес — поправить в двух файлах (по два места в
каждом) и в консоли.

## Как опубликовать

**GitHub Pages** — наружу уходит только эта папка:

```bash
git subtree push --prefix web origin gh-pages
```

Затем *Settings → Pages → Source: Deploy from a branch → Branch: `gh-pages`,
папка `/ (root)`*. Адреса:

```
https://marydaygit.github.io/GameRpgIdle/
https://marydaygit.github.io/GameRpgIdle/legal/privacy.html
https://marydaygit.github.io/GameRpgIdle/legal/delete-account.html
```

Обновить после правок — повторить ту же команду.

**Без git** — перетащить папку `web` в Cloudflare Pages или Netlify Drop;
адрес выдаётся сразу.

## Когда обновлять

Тексты описывают игру на 18.09.2026: Firebase Analytics, вход анонимный и
через Google, Cloud Firestore для сейва, без рекламы и покупок. Появится
Crashlytics, реклама, покупки или новый способ входа — обновить политику,
страницу удаления и анкету Data safety в консоли вместе.
