# Proxmox VE Safe Post-Install

**Pós-instalação conservadora, auditável e reversível para Proxmox VE 8 e 9 — em português do Brasil.**

**Tecnologias:** Bash · Proxmox VE 8/9 · Debian 12/13 · Licença MIT.

> [!IMPORTANT]
> **Não é um produto oficial da Proxmox Server Solutions ou do projeto Community Scripts.**
> O modo padrão é **somente leitura**. Alterações exigem `--configurar`, execução como root e confirmações no terminal. Nenhum script administrativo oferece garantia de 100% de segurança ou de restauração integral do sistema.

## O que é este projeto?

Uma ferramenta Bash para **verificar o host Proxmox**, **preservar suas configurações APT**, **ajustar de maneira restrita repositórios oficiais do PVE quando solicitado** e **permitir restauração das fontes APT alteradas**.

Foi criado como uma alternativa conservadora a assistentes de pós-instalação que fazem mudanças amplas, desativam serviços do cluster, alteram JavaScript da interface ou executam código remoto sem verificação prévia. **Não pretende executar a mesma quantidade de tarefas desses assistentes.**

### Princípios

- **Segurança por padrão:** `--auditar` não grava configurações, não instala pacotes e não baixa nada.
- **Consentimento explícito:** nenhuma alteração de repositório ocorre sem confirmação.
- **Sem `curl | bash`, `source <(curl ...)`, `eval` ou telemetria.**
- **Escopo restrito:** até quatro nomes predefinidos sob `/etc/apt/sources.list.d/`; nada em Ceph, HA, Corosync, VMs, interfaces gráficas ou fontes Debian.
- **Reversão verificável:** backup local, registro de mudanças (journal), hashes SHA-256 e detecção de edições posteriores.
- **Sem upgrades automáticos:** consulta/simulação de upgrades, mas **não instala, atualiza nem remove pacotes**.
- **Documentação e diagnósticos em PT-BR** (salvo a saída de ferramentas do sistema).

## Compatibilidade

| Sistema | Base Debian | Suporte | Observações |
|---|---|---|---|
| Proxmox VE 8.x | Debian 12 Bookworm | Sim | Fonte `pve-no-subscription` em arquivo `.list`, com `signed-by` apontando para chave já existente. |
| Proxmox VE 9.x | Debian 13 Trixie | Sim | Fonte `pve-no-subscription` em `deb822` (`.sources`), com `Signed-By` oficial. |
| Proxmox VE 7 e anteriores | Variável | Não | Não executar. |
| Proxmox VE 10 ou posteriores | Variável | Não verificado | Falha de propósito até nova auditoria. |
| Debian puro / VM / LXC | — | Não | Requer host Proxmox com `pveversion`. |

**Compatibilidade do código não significa certificação em hardware real:** os ensaios incluídos são laboratoriais com ambientes simulados. Veja [testes](docs/TESTES.md) e [limitações](docs/SEGURANCA.md).

## Início rápido

### 1. Confira o ambiente

Entre no **shell do host Proxmox**, preferencialmente no console ou em uma sessão SSH confiável:

```bash
pveversion
cat /etc/os-release
```

Confirme que há um backup **externo** do host e dos dados importantes antes de mudanças administrativas em produção.

### 2. Obtenha o projeto de uma fonte que você confie

**Opção A — clone de um repositório que você próprio publicou:**

```bash
git clone https://github.com/SEU-USUARIO/proxmox-ve-safe-post-install.git
cd proxmox-ve-safe-post-install
```

Substitua `SEU-USUARIO` pelo perfil verdadeiro após publicar. **O URL acima é um exemplo, não significa que o projeto já esteja online.**

**Opção B — sem Git:** transfira o ZIP da publicação, extraia no seu computador e copie apenas o script ao host, usando um mecanismo confiável (ex.: `scp`). Revise o código antes de executá-lo.

### 3. Verifique antes de rodar

```bash
bash -n post-pve-install-ptbr-seguro.sh
sha256sum post-pve-install-ptbr-seguro.sh
```

Confira o hash contra uma publicação assinada ou outro canal de confiança quando existir. **Um hash calculado a partir do mesmo arquivo não comprova sua autenticidade.**

### 4. Execute a auditoria sem alterações

```bash
bash post-pve-install-ptbr-seguro.sh --auditar
```

Esse comando exibe os arquivos de fontes APT, referências a repositórios Proxmox e aviso caso haja configuração Corosync. Não faz mudanças.

### 5. Configure somente se for necessário

```bash
sudo bash post-pve-install-ptbr-seguro.sh --configurar
```

O script exigirá terminal interativo e perguntará, individualmente, se você deseja:

1. Criar um **ponto de restauração local** e entrar no modo de configuração.
2. Adicionar o repositório `pve-no-subscription` **somente se não houver referências existentes**.
3. Desativar o `pve-enterprise` **somente se** houver um `pve-no-subscription` ativo reconhecido e o arquivo enterprise seguir o padrão simples esperado.
4. Opcionalmente executar `apt-get update` e simular `apt-get -s --no-remove dist-upgrade`, **sem instalar pacotes**.

> [!WARNING]
> **`pve-enterprise` é o canal indicado pela Proxmox para clientes com assinatura.** O canal `pve-no-subscription` não tem o mesmo nível de validação e pode não ser adequado para produção. Não desative Enterprise se sua infraestrutura usa assinatura válida.

### 6. Consulte backups e restaure alterações do assistente

```bash
sudo bash post-pve-install-ptbr-seguro.sh --listar-backups
sudo bash post-pve-install-ptbr-seguro.sh --restaurar backup-XXXXXXXX
```

O identificador `backup-XXXXXXXX` é ilustrativo; utilize um valor realmente listado pelo programa. **A restauração é restrita aos arquivos de fontes APT modificados pelo script**, e recusa sobrescrever alterações posteriores inesperadas. Consulte [guia de recuperação](docs/RECUPERACAO.md).

## Referência dos comandos

| Opção | Precisa de root? | Altera configurações? | O que acontece |
|---|---|---|---|
| Sem argumentos | Não | Não | Equivale a `--auditar`. |
| `--auditar` | Não | Não | Verificação passiva do PVE e das fontes APT. |
| `--configurar` | Sim | Sim, com confirmação | Backup e alterações restritas de fontes; consulta opcional ao APT. |
| `--listar-backups` | Pode precisar | Não | Lista pontos presentes; backups estão em diretório privado (`0700`). |
| `--restaurar ID` | Sim | Sim, com confirmação | Restaura arquivos registrados, validando hashes. |
| `--ajuda` | Não | Não | Exibe ajuda local. |

## O que a ferramenta **não** faz

Isso é uma decisão intencional de segurança — não uma instalação incompleta:

| Funcionalidade de outros scripts | Estado aqui | Motivo |
|---|---|---|
| Telemetria e envio de inventário | Removidos | Privacidade e superfície de ataque. |
| Importação de código remoto em tempo de execução | Removida | Evitar executar conteúdo mutável com privilégios de root. |
| `apt dist-upgrade` real | Não executado | Pode instalar/remover pacotes e alterar kernel; backup APT não reverte upgrade. |
| Remoção do aviso de assinatura na interface | Não incluída | Evita editar JavaScript/HTML internos do Proxmox e hooks do DPKG. |
| Reinstalação de `proxmox-widget-toolkit` e `pve-yew-mobile-gui` | Não executada | Não há alterações de UI que justifiquem reinstalar pacotes. |
| Ativação/desativação de HA ou Corosync | Não incluída | Requer conhecimento do cluster e do quorum. |
| Configuração de Ceph | Não incluída | Requer plano próprio para storage distribuído. |
| Migração PVE 8 → 9 | Não incluída | Upgrade de versão maior tem procedimento oficial específico. |
| Reinicialização automática | Não incluída | Evita interrupção de VMs e serviços. |
| Reescrita de repositórios Debian | Não incluída | Preserva configurações existentes. |

## Backup: o que é protegido?

Antes da primeira alteração de fontes, o programa salva:

```text
/var/backups/pve-postinstalacao-seguro/
└── backup-XXXXXXXX/
    ├── originais/
    │   ├── sources.list           # se existia
    │   └── sources.list.d/        # cópia de toda a pasta
    ├── alteracoes.tsv            # journal: arquivo, SHA-256 anterior e posterior
    ├── ambiente.txt              # pveversion, data UTC, uname
    └── hash_script.txt           # hash do script invocado (se disponível)
```

Os backups são privados no host. No rollback, o programa verifica o estado atual e **não sobrescreve** arquivos modificados por outro administrador após a execução.

**Não é um snapshot do host.** Não restaura pacotes, VM, contêiner, `/etc/pve`, dados ZFS/LVM, kernel, bootloader, nem reverte intervenções feitas fora do assistente. Para contingência real, implemente backups externos independentes e teste sua restauração.

## Estrutura do repositório

```text
proxmox-ve-safe-post-install/
├── post-pve-install-ptbr-seguro.sh   # executável principal
├── README.md                         # visão geral e guia de uso
├── docs/
│   ├── ARQUITETURA.md                # fluxo, decisões e controles
│   ├── COMPATIBILIDADE.md            # PVE/Debian/repos oficiais
│   ├── RECUPERACAO.md                # backup e rollback, limites
│   ├── SEGURANCA.md                  # ameaças, riscos residuais
│   ├── TESTES.md                     # verificações de laboratório e CI
│   ├── FAQ.md                        # dúvidas frequentes
│   ├── PUBLICACAO-GITHUB.md          # instruções de publicação
│   └── AUDITORIA.md                  # achados e escopo das revisões
├── tests/testar_post_pve_ptbr.py     # 16 cenários de teste isolados
├── .github/workflows/ci.yml         # testes automáticos sem root do host
├── .github/ISSUE_TEMPLATE/          # bug e solicitação de melhoria
├── .github/pull_request_template.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── CHANGELOG.md
├── NOTICE.md
├── LICENSE
└── .gitignore
```

## Qualidade e testes

Em um ambiente **Linux/WSL** de desenvolvimento ou laboratório (não é necessário root):

```bash
bash -n post-pve-install-ptbr-seguro.sh
python3 tests/testar_post_pve_ptbr.py
```

A suíte usa diretórios temporários, um `pveversion` falso, um `apt-get` falso e um terminal de testes (`script`) para exercitar fluxos sem tocar em `/etc/apt` real. O CI repete as verificações no Ubuntu. **É uma simulação, não um teste de integração em um host PVE real.**

Consulte [docs/TESTES.md](docs/TESTES.md) para saber o que é e o que não é verificado.

## Diagnóstico de problemas

| Sintoma | Significado / solução |
|---|---|
| `pveversion ausente` | Você não está em um host Proxmox compatível ou não está usando o ambiente esperado. |
| `Versão de Proxmox não aceita` | Versão fora de PVE 8/9 ou formato não reconhecido. Não force execução. |
| `PVE 9 requer Debian trixie` | A versão Proxmox/base Debian parece inconsistente. Investigue antes de prosseguir. |
| `Keyring oficial ausente` | O script não importa chaves novas. Verifique o pacote de keyring pelos procedimentos oficiais. |
| `Enterprise ... preservado` | Fonte enterprise é personalizada ou contém múltiplos blocos; não foi alterada. |
| `Já existe referência ...` | Evitou fonte duplicada. Use a GUI **Nó → Atualizações → Repositórios** para inspecionar. |
| `Rollback ... alteração posterior` | Algum arquivo mudou após o backup. Não force; compare e restaure manualmente se apropriado. |
| `Outra execução ...` | Há uma sessão em andamento ou travamento em uso. Não apague o lock enquanto outra sessão executa. |

Mais explicações no [FAQ](docs/FAQ.md) e [guia de recuperação](docs/RECUPERACAO.md).

## Segurança, contribuições e licença

- **Vulnerabilidade?** Consulte [SECURITY.md](SECURITY.md) antes de abrir uma issue pública.
- **Quer contribuir?** Leia [CONTRIBUTING.md](CONTRIBUTING.md) para os requisitos de testes e revisão.
- **Escopo técnico e riscos residuais:** [docs/SEGURANCA.md](docs/SEGURANCA.md).
- **Licença:** [MIT](LICENSE). [NOTICE.md](NOTICE.md) contém os créditos ao projeto que inspirou o fluxo.

## Documentação oficial usada como referência

- [Proxmox VE — documentação atual](https://pve.proxmox.com/pve-docs/) e [guia administrativo PVE 9](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf).
- [Proxmox VE 8 — guia administrativo](https://pve.proxmox.com/pve-docs-8/pve-admin-guide.pdf).
- [Debian — `sources.list(5)`](https://manpages.debian.org/trixie/apt/sources.list.5.en.html) e [`apt-secure(8)`](https://manpages.debian.org/trixie/apt/apt-secure.8.en.html).
- [Debian — `apt-get(8)`](https://manpages.debian.org/trixie/apt/apt-get.8.en.html).
- [GNU Bash — manual](https://www.gnu.org/software/bash/manual/bash.html).
- [GitHub — segurança no Actions](https://docs.github.com/en/actions/reference/security/secure-use).

---

**Status:** projeto publicável com 16 cenários laboratoriais; **ainda exige validação em hosts Proxmox reais antes de uso em produção**. Sem endosso oficial da Proxmox ou garantia de percentuais de ausência de falhas.
