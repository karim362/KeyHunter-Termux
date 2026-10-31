#!/data/data/com.termux/files/usr/bin/bash
# keyhunter v31 — Termux (Multi-line Custom + SDCard Copy)
set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; C='\033[0;36m'; B='\033[1m'; D='\033[2m'; M='\033[0;35m'; N='\033[0m'

OUT_DIR="$HOME/keyhunter_reports/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
HISTORY_FILE="$HOME/.keyhunter_history"
touch "$HISTORY_FILE"

# مسار الذاكرة الداخلية (SDCard)
SDCARD_DIR="/sdcard/KeyHunter"
mkdir -p "$SDCARD_DIR" 2>/dev/null || true

cleanup() {
    local exit_code=$?
    if [[ -f "$OUT_DIR/report.html" ]]; then
        find "$OUT_DIR" -type f ! -name "report.html" -delete
        
        # نسخ التقرير إلى الذاكرة الداخلية
        local phone_report="$SDCARD_DIR/report_$(date +%Y%m%d_%H%M%S).html"
        if cp "$OUT_DIR/report.html" "$phone_report" 2>/dev/null; then
            echo -e "\n${G}📱 تم نسخ التقرير إلى: ${C}$phone_report${N}"
            echo -e "${D}(يمكنك فتحه من مدير الملفات في هاتفك)${N}"
        else
            echo -e "\n${Y}⚠ لم نتمكن من النسخ إلى SDCard (صلاحيات). التقرير هنا:${N}"
            echo -e "${C}$OUT_DIR/report.html${N}"
        fi
        
        if command -v termux-open &>/dev/null; then
            termux-open "$OUT_DIR/report.html" &
        fi
    else
        rm -rf "$OUT_DIR"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

get_token() {
    local TOKEN_FILE="$HOME/.keyhunter_gh_token"
    if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
        GH_TOKEN=$(cat "$TOKEN_FILE")
    else
        printf "${Y}GitHub Token:${N} "; read -r GH_TOKEN
        [[ -n "$GH_TOKEN" ]] && echo "$GH_TOKEN" > "$TOKEN_FILE" && chmod 600 "$TOKEN_FILE"
    fi
    [[ -z "${GH_TOKEN:-}" ]] && { echo -e "${R}No token.${N}"; exit 1; }
}

strict_regex() {
    local secret="$1"; local rule="$2"; local len=${#secret}
    echo "$secret" | grep -qiE 'YOUR|EXAMPLE|XXXX|CHANGE_?ME|PLACEHOLDER|TODO|DUMMY|TEST_?KEY|FAKE' && return 1
    [[ "$secret" =~ ^(.)\1{5,}$ ]] && return 1
    case "$rule" in
        *github*) [[ "$secret" =~ ^gh[pousr]_[A-Za-z0-9]{36,}$ ]] || [[ "$secret" =~ ^github_pat_ ]] ;;
        *aws*|*AKIA*) [[ "$secret" =~ ^(AKIA|ASIA)[0-9A-Z]{16}$ ]] ;;
        *openai*) [[ "$secret" =~ ^sk-(proj-)?[A-Za-z0-9_-]{40,}$ ]] ;;
        *deepseek*) [[ "$secret" =~ ^sk-[A-Za-z0-9]{32,}$ ]] ;;
        *stripe*) [[ "$secret" =~ ^sk_live_[0-9a-zA-Z]{24,}$ ]] ;;
        *gcp*|*google*) [[ "$secret" =~ ^AIzaSy[A-Za-z0-9_-]{33}$ ]] ;;
        *huggingface*|*hf_*) [[ "$secret" =~ ^hf_[A-Za-z0-9]{34,}$ ]] ;;
        *anthropic*) [[ "$secret" =~ ^sk-ant-api03-[A-Za-z0-9_-]{80,}$ ]] ;;
        *cloudflare*) [ "$len" -ge 30 ] ;;
        *generic*|*api*key*|*sk-*|*jwt*|*private-key*) [ "$len" -ge 20 ] ;;
        *) [ "$len" -ge 8 ] ;;
    esac
}

main() {
    clear
    echo -e "${B}${C}╔══════════════════════════════════════╗${N}"
    echo -e "${B}${C}║  KEYHUNTER v31 · Termux Edition      ║${N}"
    echo -e "${B}${C}╚══════════════════════════════════════╝${N}\n"

    get_token

    echo -e "${B}اختر الهدف:${N}"
    echo -e "  ${C}1)${N} AI Keys"
    echo -e "  ${C}2)${N} CPA/Rewards"
    echo -e "  ${C}3)${N} Files & Passwords"
    echo -e "  ${C}4)${N} Custom (متعدد الأسطر: Enter فارغ للبدء)"
    echo -e "  ${C}5)${N} ALL"
    read -rp "→ " choice

    local -a QUERIES=()
    
    if [[ "$choice" == *"1"* || "$choice" == *"5"* ]]; then
        QUERIES+=("openai" "anthropic" "AIzaSy" "hf_" "sk-proj-")
    fi
    if [[ "$choice" == *"2"* || "$choice" == *"5"* ]]; then
        QUERIES+=("rapidoreach" "lootably" "adgem" "cpagrip" "ayetstudios" "tyrads")
    fi
    if [[ "$choice" == *"3"* || "$choice" == *"5"* ]]; then
        QUERIES+=("filename:.env" "filename:config" "DB_PASSWORD" "AWS_ACCESS_KEY_ID")
    fi
    
    if [[ "$choice" == *"4"* ]]; then
        echo -e "\n${B}أدخل كلمات البحث (سطر لكل كلمة):${N}"
        echo -e "${D}اكتب كلماتك، ثم اضغط Enter على سطر فارغ للبدء${N}\n"
        
        while IFS= read -r custom_kw; do
            [[ -z "$custom_kw" ]] && break
            custom_kw=$(echo "$custom_kw" | xargs)
            [[ -n "$custom_kw" ]] && QUERIES+=("$custom_kw")
        done
    fi

    [[ ${#QUERIES[@]} -eq 0 ]] && { echo -e "${R}لا شيء محدد.${N}"; exit 1; }
    
    echo -e "\n${G}✓ عدد الكلمات: ${#QUERIES[@]}${N}"

    # بناء arguments لـ ghleaks
    local -a GHL_ARGS=()
    for q in "${QUERIES[@]}"; do
        GHL_ARGS+=("-q" "$q")
    done

    # ========== المرحلة 1 ==========
    echo -e "\n${B}${C}▶ [1/3] جلب من GitHub (بحث شامل)...${N}"
    echo -e "${D}الكلمات: ${QUERIES[*]}${N}"
    echo -e "${Y}⏳ جاري البحث... (قد يستغرق دقيقة أو أكثر)${N}"
    
    local raw="$OUT_DIR/raw.jsonl"
    : > "$raw"
    
    ghleaks "${GHL_ARGS[@]}" --token "$GH_TOKEN" --report "$OUT_DIR/tmp.json" > "$OUT_DIR/gh.log" 2>&1
    
    if [[ -s "$OUT_DIR/tmp.json" ]]; then
        local found=$(jq '.findings | length' "$OUT_DIR/tmp.json" 2>/dev/null || echo 0)
        echo -e "${G}✓ تم العثور على $found نتيجة إجمالاً${N}"
        jq -c '.findings[]?' "$OUT_DIR/tmp.json" >> "$raw" 2>/dev/null || true
    else
        echo -e "${Y}⚠ لم يتم العثور على نتائج${N}"
        tail -5 "$OUT_DIR/gh.log" | sed 's/^/  /'
    fi
    rm -f "$OUT_DIR/tmp.json"

    local total_raw=$(wc -l < "$raw" 2>/dev/null || echo 0)
    [[ "$total_raw" -eq 0 ]] && { echo -e "${R}✗ لا نتائج.${N}"; exit 0; }
    echo -e "\n${G}📦 إجمالي النتائج الخام: $total_raw${N}"

    # ========== المرحلة 2 ==========
    echo -e "\n${B}${C}▶ [2/3] تصفية وبناء الروابط...${N}"
    declare -A HISTORY_HASHES
    while IFS= read -r h; do [[ -n "$h" ]] && HISTORY_HASHES["$h"]=1; done < "$HISTORY_FILE"

    local candidates="$OUT_DIR/candidates.txt"
    : > "$candidates"
    local skipped=0 skipped_history=0 valid=0

    while IFS= read -r line; do
        local secret rule file repo url
        secret=$(echo "$line" | jq -r '.Secret // .secret // empty')
        rule=$(echo "$line" | jq -r '.RuleID // .rule // "unknown"')
        file=$(echo "$line" | jq -r '.File // "unknown"')
        repo=$(echo "$line" | jq -r '.Repository // .repo // empty')
        url=$(echo "$line" | jq -r '.URL // .url // empty')
        
        [[ -z "$secret" ]] && continue
        
        if [[ -z "$url" && -n "$repo" && "$file" != "unknown" ]]; then
            url="https://github.com/$repo/blob/HEAD/$file"
        elif [[ -z "$url" && -n "$repo" ]]; then
            url="https://github.com/$repo"
        fi
        
        local hash=$(echo -n "$secret" | sha256sum | cut -d' ' -f1)
        [[ -n "${HISTORY_HASHES[$hash]:-}" ]] && { skipped_history=$((skipped_history+1)); continue; }
        
        if strict_regex "$secret" "$rule"; then
            echo "$secret|$rule|$url|$file" >> "$candidates"
            echo "$hash" >> "$HISTORY_FILE"
            valid=$((valid+1))
            printf "\r${G}🔑 مفتاح صالح #%d: ${D}%s${N}                              " "$valid" "$rule"
        else
            skipped=$((skipped+1))
        fi
    done < "$raw"
    printf "\n"

    local total_valid=$(wc -l < "$candidates")
    echo -e "${G}✓ صالحة: $total_valid${N} | ${Y}تم تخطيها: $skipped${N} | ${M}قديمة: $skipped_history${N}"
    [[ "$total_valid" -eq 0 ]] && { echo -e "${Y}لا شيء جديد للتحقق.${N}"; exit 0; }

    # ========== المرحلة 3 ==========
    echo -e "\n${B}${C}▶ [3/3] التحقق الفعلي (LIVE/DEAD)...${N}"
    echo -e "${D}فحص $total_valid مفتاح. قد يستغرق وقتاً.${N}\n"
    
    cat > "$OUT_DIR/verify.sh" << 'VEOF'
#!/data/data/com.termux/files/usr/bin/bash
data="$1"
secret=$(echo "$data" | cut -d'|' -f1)
res=$(echo "$secret" | timeout 20s trufflehog stdin --only-verified --json 2>/dev/null | head -1)
if [[ -n "$res" ]]; then echo "$data" >> "$2/live.tmp"; else echo "$data" >> "$2/dead.tmp"; fi
VEOF
    chmod +x "$OUT_DIR/verify.sh"

    : > "$OUT_DIR/live.tmp"
    : > "$OUT_DIR/dead.tmp"

    cat "$candidates" | xargs -P 4 -I {} "$OUT_DIR/verify.sh" "{}" "$OUT_DIR" &
    local VPID=$!
    local last_live=0

    while kill -0 $VPID 2>/dev/null; do
        local lc=$(wc -l < "$OUT_DIR/live.tmp" 2>/dev/null || echo 0)
        local dc=$(wc -l < "$OUT_DIR/dead.tmp" 2>/dev/null || echo 0)
        local tc=$((lc + dc))
        local pct=0
        [[ $total_valid -gt 0 ]] && pct=$((tc * 100 / total_valid))
        
        printf "\r${C}⟳${N} ${B}%3d%%${N} [%d/%d] | ${R}🔥 LIVE: %d${N} | ${D}💀 DEAD: %d${N}   " "$pct" "$tc" "$total_valid" "$lc" "$dc"
        
        if [[ $lc -gt $last_live ]]; then
            printf "\n${R}${B}🔥🔥🔥 عثرت على مفتاح حي #%d! 🔥🔥🔥${N}\n" "$lc"
            last_live=$lc
        fi
        sleep 0.5
    done
    wait $VPID
    
    local final_live=$(wc -l < "$OUT_DIR/live.tmp")
    local final_dead=$(wc -l < "$OUT_DIR/dead.tmp")
    printf "\r\033[K${G}✓${N} مكتمل! ${R}🔥 LIVE: $final_live${N} | ${D}💀 DEAD: $final_dead${N}\n"

    # ========== تقرير HTML ==========
    echo -e "\n${B}${C}▶ بناء تقرير HTML...${N}"
    local html="$OUT_DIR/report.html"

    cat > "$html" << 'HTML_HEAD'
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>KeyHunter Report</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0d1117;color:#c9d1d9;margin:0;padding:16px;font-size:15px;line-height:1.5}
h1{font-size:22px;color:#58a6ff;text-align:center;margin:0 0 8px}
h2{font-size:18px;color:#c9d1d9;border-bottom:2px solid #30363d;padding-bottom:8px;margin:24px 0 12px}
.stats{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:16px 0}
.stat{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px;text-align:center}
.stat-num{font-size:28px;font-weight:bold;display:block}
.stat-lbl{font-size:12px;color:#8b949e;margin-top:4px}
.live-num{color:#f85149}
.dead-num{color:#8b949e}
.search{width:100%;padding:14px;background:#161b22;border:1px solid #30363d;color:#fff;border-radius:10px;font-size:16px;margin-bottom:16px;outline:none}
.search:focus{border-color:#58a6ff}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;margin-bottom:12px;padding:14px;border-right:4px solid #30363d}
.card.live{border-right-color:#f85149;box-shadow:0 0 12px rgba(248,81,73,0.15)}
.card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}
.badge{font-size:11px;font-weight:bold;padding:4px 10px;border-radius:12px;background:#21262d;color:#58a6ff;text-transform:uppercase}
.card.live .badge{background:#da3633;color:#fff}
.file{font-size:12px;color:#8b949e;word-break:break-all;margin-bottom:10px;font-family:monospace}
.secret-box{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:10px;font-family:monospace;font-size:13px;word-break:break-all;color:#f0c000;margin-bottom:10px}
.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.btn{padding:12px;border-radius:8px;border:none;font-size:14px;font-weight:600;cursor:pointer;text-align:center;text-decoration:none;display:block;transition:0.2s}
.btn-copy{background:#238636;color:#fff}
.btn-copy:active{background:#2ea043}
.btn-copy.copied{background:#1f6feb}
.btn-visit{background:#1f6feb;color:#fff}
.btn-visit:active{background:#388bfd}
.btn-visit.disabled{background:#21262d;color:#8b949e;pointer-events:none}
.empty{text-align:center;color:#8b949e;padding:40px 20px;font-style:italic}
.footer{text-align:center;color:#8b949e;font-size:12px;margin-top:30px;padding-top:16px;border-top:1px solid #30363d}
</style>
<script>
function filterAll(){
  const q=document.getElementById('searchInput').value.toLowerCase();
  document.querySelectorAll('.card').forEach(c=>{
    c.style.display=c.innerText.toLowerCase().includes(q)?'':'none';
  });
}
function copySecret(btn){
  const b64=btn.getAttribute('data-b64');
  navigator.clipboard.writeText(atob(b64)).then(()=>{
    const orig=btn.innerHTML;
    btn.innerHTML='✅ تم النسخ';
    btn.classList.add('copied');
    setTimeout(()=>{btn.innerHTML=orig;btn.classList.remove('copied')},1500);
  }).catch(()=>alert('فشل النسخ، انسخ يدوياً'));
}
</script>
</head>
<body>
<h1>🎯 KeyHunter Report</h1>
<input type="text" id="searchInput" class="search" oninput="filterAll()" placeholder="🔍 ابحث...">
HTML_HEAD

    local live_count=$(wc -l < "$OUT_DIR/live.tmp")
    local dead_count=$(wc -l < "$OUT_DIR/dead.tmp")
    echo "<div class='stats'>" >> "$html"
    echo "  <div class='stat'><span class='stat-num live-num'>$live_count</span><span class='stat-lbl'>🔥 LIVE</span></div>" >> "$html"
    echo "  <div class='stat'><span class='stat-num dead-num'>$dead_count</span><span class='stat-lbl'>💀 DEAD</span></div>" >> "$html"
    echo "</div>" >> "$html"

    echo "<h2>🔥 مفاتيح حية</h2>" >> "$html"
    if [[ -s "$OUT_DIR/live.tmp" ]]; then
        while IFS='|' read -r secret rule url file; do
            [[ -z "$secret" ]] && continue
            local b64=$(echo -n "$secret" | base64 -w 0 2>/dev/null || echo -n "$secret" | base64 | tr -d '\n')
            local masked="${secret:0:10}...${secret: -4}"
            echo "<div class='card live'>" >> "$html"
            echo "  <div class='card-header'><span class='badge'>$rule</span></div>" >> "$html"
            echo "  <div class='file'>📁 $file</div>" >> "$html"
            echo "  <div class='secret-box'>$masked</div>" >> "$html"
            echo "  <div class='actions'>" >> "$html"
            echo "    <button class='btn btn-copy' data-b64='$b64' onclick=\"copySecret(this)\">📋 نسخ</button>" >> "$html"
            if [[ -n "$url" ]]; then
                echo "    <a href='$url' target='_blank' class='btn btn-visit'>🌐 المستودع</a>" >> "$html"
            else
                echo "    <a class='btn btn-visit disabled'>لا رابط</a>" >> "$html"
            fi
            echo "  </div>" >> "$html"
            echo "</div>" >> "$html"
        done < "$OUT_DIR/live.tmp"
    else
        echo "<div class='empty'>لا توجد مفاتيح حية 🎉</div>" >> "$html"
    fi

    echo "<h2>💀 مفاتيح ميتة</h2>" >> "$html"
    if [[ -s "$OUT_DIR/dead.tmp" ]]; then
        while IFS='|' read -r secret rule url file; do
            [[ -z "$secret" ]] && continue
            echo "<div class='card'>" >> "$html"
            echo "  <div class='card-header'><span class='badge'>$rule</span></div>" >> "$html"
            echo "  <div class='file'>📁 $file</div>" >> "$html"
            echo "  <div class='actions'>" >> "$html"
            if [[ -n "$url" ]]; then
                echo "    <a href='$url' target='_blank' class='btn btn-visit'>🌐 المستودع</a>" >> "$html"
            else
                echo "    <a class='btn btn-visit disabled'>لا رابط</a>" >> "$html"
            fi
            echo "  </div>" >> "$html"
            echo "</div>" >> "$html"
        done < "$OUT_DIR/dead.tmp"
    else
        echo "<div class='empty'>لا توجد مفاتيح ميتة</div>" >> "$html"
    fi

    echo "<div class='footer'>KeyHunter v31 · Termux · $(date)</div>" >> "$html"
    echo "</body></html>" >> "$html"

    echo -e "${G}✓ تم إنشاء التقرير${N}"
}

main "$@"
