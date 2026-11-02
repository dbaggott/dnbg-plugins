The plugins' repository is now `dbaggott/dnbg-plugins`, renamed from
`dbaggott/claude-plugins`. GitHub redirects the old name, but re-add the
marketplace under the new one: `/plugin marketplace remove dnbg`, then
`/plugin marketplace add dbaggott/dnbg-plugins`, then install your plugins
again, since removing a marketplace can uninstall what came from it. If your
settings name the marketplace source in `extraKnownMarketplaces`, change its
`repo` there too.
