import { Router } from "express";

export const privacyRouter = Router();

const CONTACT_EMAIL = "3czplay@gmail.com";
const LAST_UPDATED = "24. 8. 2026";

// Plain static page — no auth, no templating engine needed for one page.
// Reachable at https://sc.gabrhelovi.cz/privacy (used as the App Store
// Connect privacy policy URL).
privacyRouter.get("/privacy", (req, res) => {
  res.type("html").send(`<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Zásady ochrany osobních údajů — SharedCalendar</title>
<style>
  body { font-family: -apple-system, sans-serif; max-width: 640px; margin: 48px auto; padding: 0 20px; color: #1a1a1a; line-height: 1.5; }
  h1 { font-size: 1.6rem; }
  h2 { font-size: 1.15rem; margin-top: 2em; }
  .updated { color: #666; font-size: 0.9rem; }
  ul { padding-left: 1.2em; }
  a { color: #0a66c2; }
</style>
</head>
<body>
  <h1>Zásady ochrany osobních údajů</h1>
  <p class="updated">Naposledy aktualizováno: ${LAST_UPDATED}</p>

  <p>SharedCalendar je soukromá aplikace pro sdílený kalendář akcí mezi uzavřenou skupinou lidí. Tahle stránka popisuje, jaká data aplikace zpracovává a proč.</p>

  <h2>Jaká data se ukládají</h2>
  <ul>
    <li>Jméno a interní identifikátor z přihlášení přes Sign in with Apple.</li>
    <li>Obsah akcí, které vytvoříš — název, popis, místo, souřadnice a čas.</li>
    <li>Tvoje odpovědi na akce (jdu / nejdu) a nastavení upozornění.</li>
    <li>Push token zařízení, aby ti mohla appka poslat upozornění.</li>
    <li>Obsah bug reportů a nahlášení akcí, které sám odešleš, včetně verze appky a modelu zařízení.</li>
  </ul>

  <h2>Veřejná viditelnost akcí</h2>
  <p>Kalendář je záměrně otevřený: název, popis, místo a přesné souřadnice každé akce, spolu se jménem toho, kdo ji vytvořil, jsou viditelné komukoli, kdo appku otevře nebo navštíví odkaz na konkrétní akci na webu — přihlášení ani účet k tomu není potřeba. Přihlášení je potřeba až pro vytváření akcí a reakci na ně (jdu / nejdu). Pokud svůj účet smažeš, akce, které jsi vytvořil, se s ním smažou a přestanou být kdekoli vidět.</p>

  <h2>K čemu se data používají</h2>
  <p>Výhradně k provozu appky: zobrazení sdíleného kalendáře, doručení push upozornění, a — u nových účtů bez ověření — k omezení počtu vytvořených akcí kvůli ochraně před zneužitím.</p>

  <h2>Sdílení s třetími stranami</h2>
  <p>Data se neprodávají ani nesdílejí s reklamními či analytickými službami. Zpracovávají je jen:</p>
  <ul>
    <li><strong>Apple</strong> — přihlášení (Sign in with Apple), doručení push notifikací (APNs) a předpověď počasí pro místo akce (WeatherKit, na základě zadané adresy, ne polohy telefonu).</li>
    <li><strong>Cloudflare</strong> — jako síťová infrastruktura (tunel), kterou appka používá k připojení na server.</li>
  </ul>

  <h2>Jak dlouho se data uchovávají</h2>
  <p>Dokud existuje tvůj účet. Účet i všechna osobní data k němu vázaná můžeš kdykoli sám nenávratně smazat přímo v appce: <strong>Profil → Smazat účet</strong>.</p>

  <h2>Kontakt</h2>
  <p>Dotazy ohledně dat nebo appky: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>
</body>
</html>`);
});
