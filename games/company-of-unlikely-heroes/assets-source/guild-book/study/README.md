# Connected illustration study

`connected-study.png` is the original 1536 × 1024 output of the built-in image generator, job `image_201b75d78001YK7EeoaVkFpaln` (`openai/gpt-image-2`). SHA-256: `e4958fa9548052f79b61126ace6ba9660cca67765e4cb76fd2ae70ef3b4fd3c5`. It is an art-direction study and a preparation source, not a gameplay screenshot or a record of player acceptance.

All four plates are 750 × 497. ImageMagick extraction from this directory:

```sh
magick connected-study.png -crop 750x497+10+10   +repage destination-plate.png
magick connected-study.png -crop 750x497+776+10  +repage portrait-plate.png
magick connected-study.png -crop 750x497+10+518  +repage report-plate.png
magick connected-study.png -crop 750x497+776+518 +repage reward-plate.png
```

At game size, the destination needs its crossing visible in both wide crops; the portrait needs the face centered high enough to survive a small reward-owner crop. Keep space around scout crayon marks and reward objects, rather than filling the full card with detail. The painting, portrait, sketch and upgrade should remain distinguishable without their captions.
