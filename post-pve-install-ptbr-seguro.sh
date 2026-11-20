#!/usr/bin/env bash
# Pós-instalação conservadora do Proxmox VE 8/9 — Português do Brasil.
# Implementação independente, inspirada no fluxo Community Scripts (licença MIT).
# https://github.com/community-scripts/ProxmoxVE
# NÃO é distribuído nem homologado pelo Proxmox ou Community Scripts.
#
# Princípios: sem rede exceto apt-get update opcional, sem execução de scripts
# remotos, sem telemetria, sem upgrades automáticos, sem alterar HA/Corosync,
# Ceph, interface web, configuração de rede nem máquinas virtuais.
# Alterações de fontes APT são opt-in e possuem journal com rollback validado.
# O rollback NÃO desfaz instalações/updates de pacotes feitas FORA do script.
#
# Referências: Proxmox VE Admin Guide; Debian sources.list(5), apt-secure(8),
# apt-get(8); GNU Bash Reference Manual.

set -Eeuo pipefail
shopt -s nullglob
umask 077
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'
export LC_ALL=C

readonly RAIZ_BACKUPS='/var/backups/pve-postinstalacao-seguro'
readonly APT_DIR='/etc/apt'
BACKUP_DIR=''
PVE_MAJOR=''
PVE_VERSION=''
SUITE=''
EM_CONFIGURACAO=0

info() { printf '[INFO] %s\n' "$*"; }
aviso() { printf '[AVISO] %s\n' "$*" >&2; }
fatal() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

falha_inesperada() {
  local rc="$1" linha="$2"
  printf '[ERRO] Falha inesperada na linha %s (código %s).\n' "$linha" "$rc" >&2
  if [[ -n "$BACKUP_DIR" ]]; then
    printf '[ALERTA] Ponto de restauração: %s\n' "$BACKUP_DIR" >&2
    printf '[ALERTA] Execute --restaurar %s para reverter APENAS as alterações de fontes APT.\n' "${BACKUP_DIR##*/}" >&2
  fi
  exit "$rc"
}
trap 'falha_inesperada "$?" "$LINENO"' ERR

# Protege contra interrupção e abortos depois de uma primeira alteração.
# A restauração automática é somente de arquivos que ainda correspondem aos
# hashes registrados. SIGKILL/falha de energia não permitem executar traps;
# nesses casos usar --restaurar manualmente.
ao_sair() {
  local rc="$1"
  if [[ "$rc" != 0 && "$EM_CONFIGURACAO" == 1 && -n "$BACKUP_DIR" ]]; then
    trap - ERR
    set +e
    aviso 'Execução interrompida: tentando reverter as alterações deste assistente.'
    restaurar_arquivos_registrados
    local reverteu="$?"
    if [[ "$reverteu" == 0 ]]; then
      aviso 'Rollback automático das fontes APT concluído.'
    else
      aviso "Rollback automático INCOMPLETO. Faça inspeção manual: $BACKUP_DIR"
    fi
  fi
}
trap 'ao_sair "$?"' EXIT

ajuda() {
  cat <<'FIM'
PÓS-INSTALAÇÃO SEGURA PROXMOX VE 8/9 — PT-BR

Uso (no HOST Proxmox, não dentro de LXC/VM):
  bash post-pve-install-ptbr-seguro.sh --auditar             # padrão; só leitura
  bash post-pve-install-ptbr-seguro.sh --configurar          # opt-in por operação
  bash post-pve-install-ptbr-seguro.sh --listar-backups      # identifica pontos
  bash post-pve-install-ptbr-seguro.sh --restaurar ID        # reverte fontes alteradas
  bash post-pve-install-ptbr-seguro.sh --ajuda

A restauração exige root e terminal interativo. ID é o nome da pasta do backup,
por exemplo: backup-AB12CDEF. Cada arquivo é restaurado somente se seu hash
corresponder ao estado aplicado pelo assistente; modificações posteriores
impedem a restauração para não apagar trabalho de terceiros.

Escopo do backup: cópia de /etc/apt/sources.list e /etc/apt/sources.list.d,
mais journal e informações do ambiente. NÃO é snapshot integral do servidor:
não restaura kernel, pacotes, sistemas de arquivos, VMs ou contêineres.
Faça backup externo/snapshot do HOST antes de qualquer atualização crítica.

O programa não executa dist-upgrade, reinicialização, remoção de nag, Ceph,
HA/Corosync, redes, migração de versão nem alteração dos repositórios Debian.
FIM
}

confirmar() {
  local pergunta="$1" resposta
  while :; do
    printf '%s [s/N]: ' "$pergunta"
    if ! IFS= read -r resposta; then
      fatal 'Sem entrada interativa; interrompido com segurança.'
    fi
    case "${resposta,,}" in
      s|sim) return 0 ;;
      ''|n|nao|não) return 1 ;;
      *) printf 'Responda S (sim) ou N (não).\n' ;;
    esac
  done
}

exigir_root_terminal() {
  [[ "$EUID" == 0 ]] || fatal 'Esta operação exige root no host.'
  [[ -t 0 && -t 1 ]] || fatal 'Esta operação exige terminal interativo (TTY).'
  command -v flock >/dev/null || fatal 'Comando flock (util-linux) não encontrado.'
  [[ ! -L "$RAIZ_BACKUPS" ]] || fatal 'Pasta de backups é um link simbólico; interrompido.'
  install -d -m 0700 -- "$RAIZ_BACKUPS"
  chmod 0700 -- "$RAIZ_BACKUPS"
  exec 9>"$RAIZ_BACKUPS/.lock"
  flock -n 9 || fatal 'Outra execução do assistente está em andamento.'
}

verificar_host() {
  command -v pveversion >/dev/null 2>&1 || fatal 'pveversion ausente: use somente no host Proxmox.'
  command -v apt-get >/dev/null 2>&1 || fatal 'apt-get não disponível.'
  [[ -r /etc/os-release ]] || fatal 'Arquivo /etc/os-release ausente.'
  grep -Eq '^ID="?debian"?$' /etc/os-release || fatal 'A base do host não é Debian.'
  local codename saida
  codename="$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)"
  codename="${codename//\"/}"
  saida="$(pveversion)" || fatal 'pveversion falhou.'
  [[ "$saida" =~ ^pve-manager/([89])\.([0-9]+)\.([0-9]+) ]] || fatal "Versão de Proxmox não aceita: $saida"
  PVE_MAJOR="${BASH_REMATCH[1]}"
  PVE_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  if [[ "$PVE_MAJOR" == 8 ]]; then SUITE='bookworm'; else SUITE='trixie'; fi
  [[ "$codename" == "$SUITE" ]] || fatal "PVE $PVE_MAJOR requer Debian $SUITE; identificado '$codename'."
  [[ -d "$APT_DIR/sources.list.d" && ! -L "$APT_DIR/sources.list.d" ]] || fatal 'Diretório APT inválido.'
  info "Host: Proxmox VE $PVE_VERSION / Debian $SUITE."
}

mostrar_estado() {
  info 'Arquivos de repositórios APT presentes:'
  [[ -f "$APT_DIR/sources.list" ]] && printf '%s\n' "  $APT_DIR/sources.list"
  find "$APT_DIR/sources.list.d" -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print | sort
  info 'Referências ao Proxmox (inclui comentários e fontes desativadas):'
  grep -hEn 'pve-enterprise|pve-no-subscription|pve-test|ceph-' \
    "$APT_DIR/sources.list" "$APT_DIR"/sources.list.d/*.list "$APT_DIR"/sources.list.d/*.sources \
    2>/dev/null || true
  if [[ -f /etc/pve/corosync.conf ]]; then
    aviso 'Cluster Corosync identificado. NÃO será alterado.'
  fi
  aviso 'Debian, Ceph, HA, Corosync e interface web permanecerão intactos.'
  aviso 'Se o host tem assinatura enterprise, prefira manter esse canal.'
}

# Backup de configuração + inventário antes de qualquer escrita em fontes.
# Uma cópia integra também serve para recuperação MANUAL em emergências.
criar_ponto_restauracao() {
  [[ -z "$BACKUP_DIR" ]] || return 0
  BACKUP_DIR="$(mktemp -d "$RAIZ_BACKUPS/backup-XXXXXXXX")"
  chmod 0700 "$BACKUP_DIR"
  install -d -m 0700 "$BACKUP_DIR/originais"
  if [[ -e "$APT_DIR/sources.list" ]]; then
    [[ -f "$APT_DIR/sources.list" && ! -L "$APT_DIR/sources.list" ]] || fatal 'sources.list inválido.'
    cp -a -- "$APT_DIR/sources.list" "$BACKUP_DIR/originais/"
  fi
  cp -a -- "$APT_DIR/sources.list.d" "$BACKUP_DIR/originais/"
  sync -f "$BACKUP_DIR/originais/sources.list.d" || fatal 'Falha ao persistir cópia das fontes.'
  (pveversion && date -u '+UTC: %Y-%m-%dT%H:%M:%SZ' && uname -a) > "$BACKUP_DIR/ambiente.txt"
  sha256sum -- "$0" > "$BACKUP_DIR/hash_script.txt" || true
  : > "$BACKUP_DIR/alteracoes.tsv"
  chmod 0600 "$BACKUP_DIR/alteracoes.tsv" "$BACKUP_DIR/ambiente.txt"
  info "PONTO DE RESTAURAÇÃO CRIADO: $BACKUP_DIR"
}

# Só permite destinos gerenciados pelo assistente. Backup e hash são registrados
# ANTES da substituição; interrupção posterior ainda permite restaurar.
permitir_caminho() {
  case "$1" in
    "$APT_DIR/sources.list.d/pve-enterprise.list"| \
    "$APT_DIR/sources.list.d/pve-enterprise.sources"| \
    "$APT_DIR/sources.list.d/post-pve-ptbr-no-subscription.list"| \
    "$APT_DIR/sources.list.d/post-pve-ptbr-no-subscription.sources") return 0 ;;
    *) return 1 ;;
  esac
}

hash_arquivo() {
  if [[ -f "$1" && ! -L "$1" ]]; then
    sha256sum -- "$1" | awk '{print $1}'
  elif [[ ! -e "$1" && ! -L "$1" ]]; then
    printf 'AUSENTE\n'
  else
    return 1
  fi
}

registrar_e_aplicar() {
  local destino="$1" novo="$2" anterior posterior tmp
  permitir_caminho "$destino" || fatal "Destino não autorizado: $destino"
  [[ -n "$BACKUP_DIR" ]] || fatal 'Backup não criado.'
  [[ -f "$novo" && ! -L "$novo" ]] || fatal 'Arquivo temporário inválido.'
  anterior="$(hash_arquivo "$destino")" || fatal "Destino inseguro: $destino"
  posterior="$(hash_arquivo "$novo")" || fatal 'Falha ao calcular hash da alteração.'
  [[ "$anterior" != "$posterior" ]] || { rm -f -- "$novo"; info 'Arquivo já está correto, nenhuma alteração.'; return 0; }
  local copia="$BACKUP_DIR/originais/sources.list.d/${destino##*/}"
  if [[ "$anterior" != 'AUSENTE' ]]; then
    [[ -f "$copia" && ! -L "$copia" ]] || fatal "Backup original ausente: $copia"
    [[ "$(hash_arquivo "$copia")" == "$anterior" ]] || fatal 'Backup inconsistente; abortado.'
    chown --reference="$destino" -- "$novo"
    chmod --reference="$destino" -- "$novo"
  else
    chmod 0644 "$novo"
  fi
  # Registro resistente a interrupção: contém estado antigo e futuro.
  printf '%s\t%s\t%s\n' "${destino##*/}" "$anterior" "$posterior" >> "$BACKUP_DIR/alteracoes.tsv"
  sync -f "$BACKUP_DIR/alteracoes.tsv" || fatal 'Não foi possível persistir o journal.'
  [[ "$(hash_arquivo "$destino")" == "$anterior" ]] || fatal 'Arquivo mudou durante operação; interrompido.'
  mv -T -- "$novo" "$destino"
  sync -f "$destino" || fatal 'Não foi possível persistir a alteração.'
  [[ "$(hash_arquivo "$destino")" == "$posterior" ]] || fatal 'Hash da edição diferente do previsto.'
  info "Alteração registrada e aplicada: $destino"
}

# Conservador: só reconhece o arquivo empresarial padrão. Se houver vários
# blocos deb822 ou um layout personalizado, recusa editar automaticamente.
desativar_enterprise_padrao() {
  local arquivo temporario
  if [[ "$PVE_MAJOR" == 8 ]]; then
    arquivo="$APT_DIR/sources.list.d/pve-enterprise.list"
    [[ -f "$arquivo" && ! -L "$arquivo" ]] || { aviso 'Enterprise não localizado no arquivo padrão do PVE 8.'; return 0; }
    temporario="$(mktemp "${arquivo}.tmp-XXXXXXXX")"
    if ! awk '
      /^[[:space:]]*deb[[:space:]]+https:\/\/enterprise\.proxmox\.com\/debian\/pve[[:space:]]+bookworm[[:space:]]+pve-enterprise[[:space:]]*$/ {
        print "# Desativado pelo assistente PT-BR: " $0; alterou=1; next
      }
      { print }
      END { if (!alterou) exit 3 }
    ' "$arquivo" > "$temporario"; then
      rm -f -- "$temporario"
      aviso 'Arquivo enterprise 8 com padrão diferente; não será modificado.'
      return 0
    fi
  else
    arquivo="$APT_DIR/sources.list.d/pve-enterprise.sources"
    [[ -f "$arquivo" && ! -L "$arquivo" ]] || { aviso 'Enterprise não localizado no arquivo padrão do PVE 9.'; return 0; }
    if ! awk '
      /^Types:/ {t++}
      /^URIs:[[:space:]]*https:\/\/enterprise\.proxmox\.com\/debian\/pve[[:space:]]*$/ {u++}
      /^Components:[[:space:]]*pve-enterprise[[:space:]]*$/ {c++}
      /^Suites:[[:space:]]*trixie[[:space:]]*$/ {s++}
      /^Enabled:/ {e++; if ($0 ~ /^Enabled:[[:space:]]*no[[:space:]]*$/) off++}
      END {exit !(t==1 && u==1 && c==1 && s==1 && e<=1 && off==0)}
    ' "$arquivo"; then
      aviso 'Arquivo enterprise 9 é personalizado, possui blocos adicionais ou já está desativado; preservado.'
      return 0
    fi
    temporario="$(mktemp "${arquivo}.tmp-XXXXXXXX")"
    if grep -q '^Enabled:' "$arquivo"; then
      awk '/^Enabled:/ {print "Enabled: no"; next} {print}' "$arquivo" > "$temporario"
    else
      awk '{print} /^Components:[[:space:]]*pve-enterprise[[:space:]]*$/ {print "Enabled: no"}' "$arquivo" > "$temporario"
    fi
  fi
  registrar_e_aplicar "$arquivo" "$temporario"
}

# Inclui entradas inativas para EVITAR novos arquivos que provoquem conflito
# com Signed-By. A ativação da existente deve ser feita manualmente via GUI.
existe_no_subscription() {
  local arquivo
  if [[ -f "$APT_DIR/sources.list" ]] && grep -q 'pve-no-subscription' "$APT_DIR/sources.list"; then return 0; fi
  for arquivo in "$APT_DIR"/sources.list.d/*.list "$APT_DIR"/sources.list.d/*.sources; do
    [[ -f "$arquivo" ]] || continue
    grep -q 'pve-no-subscription' "$arquivo" && return 0
  done
  return 1
}


# Regra de segurança: não desativar a ÚNICA fonte de pacotes Proxmox.
# Reconhece apenas a origem oficial, o codename correto e stanzas ativas.
# Em caso de formato desconhecido, prefere retornar falso (fail closed).
tem_no_subscription_ativo() {
  local arquivo
  for arquivo in "$APT_DIR/sources.list" "$APT_DIR"/sources.list.d/*.list; do
    [[ -f "$arquivo" && ! -L "$arquivo" ]] || continue
    if grep -Eq "^[[:space:]]*deb[[:space:]]+(\\[[^]]+\\][[:space:]]+)?https?://download[.]proxmox[.]com/debian/pve[[:space:]]+$SUITE[[:space:]]+pve-no-subscription([[:space:]]|$)" "$arquivo"; then
      return 0
    fi
  done
  for arquivo in "$APT_DIR"/sources.list.d/*.sources; do
    [[ -f "$arquivo" && ! -L "$arquivo" ]] || continue
    if awk -v suite="$SUITE" '
      function flush() {
        if (tipo && uri && versao && componente && !desativado) encontrado=1
        tipo=uri=versao=componente=desativado=0
      }
      /^[[:space:]]*$/ {flush(); next}
      /^[[:space:]]*#/ {next}
      /^Types:[[:space:]]/ {if ($0 ~ /(^|[[:space:]])deb([[:space:]]|$)/) tipo=1}
      /^URIs:[[:space:]]/ {if ($0 ~ /https?:\/\/download[.]proxmox[.]com\/debian\/pve([[:space:]]|$)/) uri=1}
      /^Suites:[[:space:]]/ {s=$0; sub(/^Suites:[[:space:]]*/, "", s); if (s == suite) versao=1}
      /^Components:[[:space:]]/ {if ($0 ~ /(^|[[:space:]])pve-no-subscription([[:space:]]|$)/) componente=1}
      /^Enabled:[[:space:]]*/ {if ($0 ~ /^Enabled:[[:space:]]*(no|false|0)[[:space:]]*$/) desativado=1}
      END {flush(); exit !encontrado}
    ' "$arquivo"; then
      return 0
    fi
  done
  return 1
}

adicionar_no_subscription() {
  local arquivo chave tmp
  if existe_no_subscription; then
    aviso 'Já existe referência pve-no-subscription (possivelmente desativada).'
    aviso 'Para evitar duplicidade, nada foi criado. Revise em Nó > Atualizações > Repositórios.'
    return 0
  fi
  if [[ "$PVE_MAJOR" == 9 ]]; then
    chave='/usr/share/keyrings/proxmox-archive-keyring.gpg'
    [[ -s "$chave" && ! -L "$chave" ]] || fatal "Keyring oficial ausente: $chave"
    arquivo="$APT_DIR/sources.list.d/post-pve-ptbr-no-subscription.sources"
    [[ ! -e "$arquivo" && ! -L "$arquivo" ]] || fatal "Destino já existe: $arquivo"
    tmp="$(mktemp "${arquivo}.tmp-XXXXXXXX")"
    cat > "$tmp" <<'FIM'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
FIM
  else
    if [[ -s /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg ]]; then
      chave='/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg'
    elif [[ -s /usr/share/keyrings/proxmox-archive-keyring.gpg ]]; then
      chave='/usr/share/keyrings/proxmox-archive-keyring.gpg'
    else
      fatal 'Keyring oficial do Proxmox VE 8 ausente; repositório não criado.'
    fi
    arquivo="$APT_DIR/sources.list.d/post-pve-ptbr-no-subscription.list"
    [[ ! -e "$arquivo" && ! -L "$arquivo" ]] || fatal "Destino já existe: $arquivo"
    tmp="$(mktemp "${arquivo}.tmp-XXXXXXXX")"
    printf 'deb [signed-by=%s] http://download.proxmox.com/debian/pve bookworm pve-no-subscription\n' "$chave" > "$tmp"
  fi
  registrar_e_aplicar "$arquivo" "$tmp"
  aviso 'O canal no-subscription é voltado a homelab/testes, não equivale ao enterprise.'
}

# Apenas índices e simulação. Nenhuma instalação/remoção de pacotes é feita.
verificar_atualizacoes() {
  info 'O comando apt-get update obtém índices autenticados pelo APT (sem instalar pacotes).'
  if confirmar 'Atualizar os índices dos repositórios agora?'; then
    apt-get -o APT::Update::Error-Mode=any update || fatal 'Falha na atualização de índices. Verifique a saída.'
  fi
  info 'Simulação de atualização (apt-get -s --no-remove dist-upgrade):'
  apt-get -s --no-remove dist-upgrade || fatal 'Simulação do APT falhou.'
  aviso 'NENHUMA atualização de pacotes foi instalada. Para isso, siga o fluxo oficial do Proxmox.'
}

listar_backups() {
  [[ -d "$RAIZ_BACKUPS" ]] || { info 'Nenhum backup encontrado.'; return 0; }
  info "Pontos disponíveis em $RAIZ_BACKUPS:"
  local dir
  for dir in "$RAIZ_BACKUPS"/backup-????????; do
    [[ -d "$dir" && ! -L "$dir" ]] || continue
    [[ -f "$dir/alteracoes.tsv" ]] || continue
    printf '%s\n' "  ${dir##*/}"
  done
}

# A mesma rotina serve para o rollback interativo e o rollback automático.
# A primeira passagem valida TUDO; não restaura parcialmente por um conflito
# conhecido antes de começar. Um conflito concorrente durante o processo para
# a restauração, preservando os demais arquivos.
restaurar_arquivos_registrados() {
  local pasta="$BACKUP_DIR" manifesto nome antes depois arquivo copia atual extra i tmp
  local -a nomes=() anteriores=() posteriores=()
  [[ -n "$pasta" && -d "$pasta" && ! -L "$pasta" ]] || { aviso 'Pasta do backup inválida.'; return 1; }
  manifesto="$pasta/alteracoes.tsv"
  [[ -f "$manifesto" && ! -L "$manifesto" && -d "$pasta/originais/sources.list.d" ]] || {
    aviso 'Journal ou arquivos originais não encontrados.'; return 1;
  }
  while IFS=$'\t' read -r nome antes depois extra || [[ -n "$nome" ]]; do
    [[ -n "$nome" ]] || continue
    [[ -z "${extra:-}" && "$nome" =~ ^[a-zA-Z0-9._-]+$ ]] || { aviso 'Journal inválido.'; return 1; }
    arquivo="$APT_DIR/sources.list.d/$nome"
    permitir_caminho "$arquivo" || { aviso 'Destino proibido no journal.'; return 1; }
    [[ "$antes" == AUSENTE || "$antes" =~ ^[a-f0-9]{64}$ ]] || { aviso 'Hash de origem inválido.'; return 1; }
    [[ "$depois" =~ ^[a-f0-9]{64}$ ]] || { aviso 'Hash do estado alterado inválido.'; return 1; }
    copia="$pasta/originais/sources.list.d/$nome"
    if [[ "$antes" != AUSENTE ]]; then
      [[ -f "$copia" && ! -L "$copia" ]] || { aviso 'Cópia original perdida.'; return 1; }
      [[ "$(hash_arquivo "$copia")" == "$antes" ]] || { aviso 'Backup não passou na verificação SHA-256.'; return 1; }
    fi
    atual="$(hash_arquivo "$arquivo")" || { aviso 'Destino inesperado ou link simbólico.'; return 1; }
    [[ "$atual" == "$antes" || "$atual" == "$depois" ]] || {
      aviso "O arquivo $nome foi modificado após a configuração: nenhuma restauração será iniciada."; return 1;
    }
    nomes+=("$nome"); anteriores+=("$antes"); posteriores+=("$depois")
  done < "$manifesto"
  for ((i=0; i<${#nomes[@]}; i++)); do
    nome="${nomes[i]}"; antes="${anteriores[i]}"; depois="${posteriores[i]}"
    arquivo="$APT_DIR/sources.list.d/$nome"; copia="$pasta/originais/sources.list.d/$nome"
    atual="$(hash_arquivo "$arquivo")" || return 1
    [[ "$atual" == "$antes" ]] && continue
    [[ "$atual" == "$depois" ]] || { aviso "Alteração concorrente em $nome."; return 1; }
    if [[ "$antes" == AUSENTE ]]; then
      rm -- "$arquivo" || return 1
      sync -f "$APT_DIR/sources.list.d" || return 1
    else
      tmp="$(mktemp "${arquivo}.restore-XXXXXXXX")" || return 1
      cp -a -- "$copia" "$tmp" || { rm -f -- "$tmp"; return 1; }
      mv -T -- "$tmp" "$arquivo" || { rm -f -- "$tmp"; return 1; }
      sync -f "$arquivo" || return 1
    fi
    [[ "$(hash_arquivo "$arquivo")" == "$antes" ]] || { aviso "Integridade falhou após restaurar $nome."; return 1; }
    info "Restaurado: $arquivo"
  done
  return 0
}

restaurar() {
  local id="$1" pasta
  [[ "$id" =~ ^backup-[a-zA-Z0-9]{8}$ ]] || fatal 'ID inválido. Use --listar-backups.'
  pasta="$RAIZ_BACKUPS/$id"
  [[ -d "$pasta" && ! -L "$pasta" && -f "$pasta/alteracoes.tsv" ]] || fatal 'Ponto inexistente ou inválido.'
  BACKUP_DIR="$pasta"
  info "Ponto de restauração escolhido: $id"
  confirmar 'Restaurar SOMENTE as fontes APT modificadas neste ponto?' || { info 'Cancelado.'; return 0; }
  restaurar_arquivos_registrados || fatal 'Restauração NÃO concluída; revise o journal e o backup.'
  info 'Restauração concluída. Fontes APT alheias preservadas.'
  aviso 'O rollback não desfaz eventuais atualizações/alterações externas.'
}

principal() {
  local modo="${1:---auditar}"
  case "$modo" in
    --ajuda|-h|--help) ajuda; return 0 ;;
    --auditar) [[ "$#" -le 1 ]] || fatal 'Argumentos extras.'; verificar_host; mostrar_estado; info 'Somente leitura; nenhuma alteração.' ;;
    --listar-backups) [[ "$#" == 1 ]] || fatal 'Argumentos extras.'; listar_backups ;;
    --restaurar)
      [[ "$#" == 2 ]] || fatal 'Informe o ID obtido com --listar-backups.'
      verificar_host; exigir_root_terminal; restaurar "$2" ;;
    --configurar)
      [[ "$#" == 1 ]] || fatal 'Argumentos extras.'
      verificar_host; exigir_root_terminal; mostrar_estado
      aviso 'Não realiza migração PVE 8 -> PVE 9 nem garante recuperação do sistema completo.'
      confirmar 'Criar ponto de restauração e entrar na configuração?' || { info 'Cancelado sem alterações.'; return 0; }
      criar_ponto_restauracao
      EM_CONFIGURACAO=1
      if confirmar 'Adicionar pve-no-subscription SOMENTE se nenhuma referência existir?'; then
        adicionar_no_subscription
      fi
      if tem_no_subscription_ativo; then
        if confirmar 'Desativar pve-enterprise SOMENTE se estiver no padrão oficial simples?'; then
          desativar_enterprise_padrao
        fi
      else
        aviso 'Por segurança, não desativarei o enterprise sem um pve-no-subscription ativo e reconhecido.'
        aviso 'Se há uma assinatura válida, mantenha o enterprise. Caso contrário, ajuste fontes manualmente.'
      fi
      if confirmar 'Atualizar índices e simular as atualizações (SEM instalar pacotes)?'; then
        verificar_atualizacoes
      fi
      EM_CONFIGURACAO=0
      info "Assistente concluído. Backup: $BACKUP_DIR"
      info "Para desfazer as fontes alteradas: bash $0 --restaurar ${BACKUP_DIR##*/}"
      aviso 'Apenas fontes APT foram modificadas. Não houve atualizações de pacotes nem reinício.'
      ;;
    *) ajuda; fatal "Opção desconhecida: $modo" ;;
  esac
}

principal "$@"
