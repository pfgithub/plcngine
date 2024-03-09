ui notes:

- no alpha blending, everything specifies a background color
- depth map writing
- one draw call for everything
  - could be instanced? vertex data is a rect & instance data is ul,br
- this limits the maximum pretty of the ui (no alpha blending) but we can make it consistent

- later on we can make a fancy ui shader with rounded borders and shadows and alpha blending





todo:

- [x] fix mem leak
- [ ] make camera lead movement not follow it (while moving right, player shifts to the left of the screen based on speed)
- [ ] switch from location to names (assuming it's supported on the zig side)
- ui stuff
 - [x] switch ui shader
- [ ] in texture sampling, around the border of two pixels blend the colors
  - [ ] here it would be nice if the textures stored color data because then we could use the default sampler