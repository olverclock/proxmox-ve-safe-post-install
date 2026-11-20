# Política de segurança

## Como relatar uma vulnerabilidade

**Não publique detalhes exploráveis, segredos, IPs privados ou logs sensíveis em issues públicas.** Use preferencialmente a opção **Security → Advisories → Report a vulnerability** no GitHub deste repositório, se estiver habilitada pelo mantenedor.

Se a opção não estiver disponível, entre em contato **privadamente com o mantenedor** por um canal que ele tenha publicado. Não há endereço de e-mail oficial definido neste pacote, e nenhum tempo de resposta é prometido.

Ao relatar, forneça versão/commit, ambiente (PVE 8/9, Debian), passos mínimos de reprodução sem dados sensíveis, impacto e mitigação possível.

## Escopo de suporte

- Script e testes contidos neste repositório.
- Erros de alteração de fontes APT, integridade dos backups locais e rollback.
- Riscos de execução inesperada ou comportamento contrário ao escopo documentado.

Não oferecemos suporte oficial a produtos Proxmox/Debian nem a pacotes de terceiros. O uso do script no host é responsabilidade do administrador; teste antes em ambiente controlado.

## Princípios de atualização segura

Modificações de segurança devem incluir teste de regressão para a falha e revisão manual. Evite adicionar downloads dinâmicos de Bash, telemetria ou mecanismos que ignorem assinaturas dos repositórios.
