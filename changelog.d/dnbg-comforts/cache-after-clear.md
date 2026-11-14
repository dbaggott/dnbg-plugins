Fixed the usage band's prompt-cache estimate sticking at `cache none` after a
`/clear`. It now counts down again from the first turn that finishes after the
clear, and the model-switch and saved-model notices in the band also work again
after a `/clear`.
