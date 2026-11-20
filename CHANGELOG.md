# Histórico de mudanças

Este projeto utiliza um histórico legível; versões futuras poderão adotar [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-11-20

### Adicionado
- Script em PT-BR com auditoria passiva, configuração por confirmação e backup de fontes APT.
- Journal SHA-256 e recuperação seletiva de arquivos alterados pelo assistente.
- Compatibilidade planejada para PVE 8/Bookworm e PVE 9/Trixie.
- 16 cenários de teste isolados e CI inicial.
- Documentação completa, política de segurança e orientações de publicação.

### Excluído intencionalmente
- Telemetria, execução de shell remoto, upgrades reais, mudanças em HA/Corosync/Ceph, patches da interface web, reinicialização automática e edição indiscriminada de fontes Debian.

### Observações
- Não houve teste de integração em hosts Proxmox de produção neste pacote.
