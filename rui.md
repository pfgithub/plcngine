ui notes:

- no alpha blending, everything specifies a background color
- depth map writing
- one draw call for everything
- this limits the maximum pretty of the ui (no alpha blending) but we can make it consistent





todo:

- [ ] fix mem leak
- [ ] make camera lead movement not follow it (while moving right, player shifts to the left of the screen based on speed)
- ui stuff
- [ ] in texture sampling, around the border of two pixels blend the colors
  - [ ] here it would be nice if the textures stored color data because then we could use the default sampler