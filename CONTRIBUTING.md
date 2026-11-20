# Como contribuir

Obrigado pelo interesse! Este projeto modifica repositórios de um **hipervisor**, portanto mudanças devem ser pequenas, auditáveis e testadas.

## Antes de abrir um pull request

1. Abra uma issue para mudanças que ampliem o escopo (instalação real de pacotes, Ceph, HA, Corosync, patches de UI, migrações de versão).
2. Não remova o modo somente leitura como padrão nem contorne confirmações.
3. Não introduza execução remota de shell, telemetria obrigatória ou desativação de checagens APT.
4. Adicione testes positivos e negativos quando modificar um fluxo.
5. Atualize o README, CHANGELOG e a documentação de recuperação se necessário.
6. Não inclua credenciais, inventários reais ou arquivos `/etc/apt` de máquinas identificáveis.

## Verificações obrigatórias

```bash
bash -n post-pve-install-ptbr-seguro.sh
python3 tests/testar_post_pve_ptbr.py
```

Execute ShellCheck adicionalmente se o tiver instalado; divergências devem ser justificadas no PR. **Nenhum teste automatizado deve escrever em caminhos reais do host.**

## Recomendações de revisão

PRs que alteram backup, journal ou rollback requerem especial atenção a interrupções, links simbólicos, concorrência e arquivos personalizados. Se a alteração mudar o comportamento observável, documente antes/depois e forneça exemplos de saída.

Consulte [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) para as regras de convivência.
