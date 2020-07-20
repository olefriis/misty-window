# Raindrops and Mist (in Metal)

Alert: This repo contains very messy code. It is my first foray into using Metal on iOS and is mainly
meant as a learning exercise. Don't expect well-structured or well-documented code. Oh, and if you want
to see even shittier code, look no further than `git log`...

## Enough talk! Show me what it looks like!

![Showcase](./Showcase.gif)

This is just a small example of using Metal. By using the iOS camera and doing some image processing,
it makes it look like your iPhone is a foggy piece of glass with raindrops rolling down.

The raindrops will make the fog temporarily disappear in their trace. If you turn your phone, the
raindrops will change direction accordingly. You can wipe the fog off the screen with your fingers.

## What's missing

As mentioned, this is just my own experiments with Metal. So if you want, you are more than welcome to
fix a few things I haven't got around to:

* The raindrops look too perfect. It'd be nice to randomize their looks a bit. Maybe add raindrops of
  different sizes? Also, how about merging raindrops if they get too close to each other. And letting
  raindrops leave smaller raindrops in their paths?
* Probably a few race conditions in the code, as I haven't focused on that part.
* Get it working with 60 FPS. I _guess_ it's relatively easy to get the camera data 60 times a second,
  but frankly I've no clue. And I think currently we're pretty hard on the GPU, so perhaps 60 FPS is
  not a possibility per se.
* My Swift fu is far from perfect. Probably lots of places where I should conver the code to more
  idiomatic Swift.

## How was this done?

...

## Acknowledgements
This experiment is _heavily_ inspired by the "The Drive Home" tutorials from
[The Art of Code](https://www.youtube.com/channel/UCcAlTqd9zID6aNX3TzwxJXg). These are really awesome
introductions to writing shaders.

Getting up and running with Metal was made possible for me by reading a few articles on
[Metal by Example](https://metalbyexample.com). Lots of great stuff there!

## License

