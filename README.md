## mtlx-to-osl

---

This repository implements a wrapper around [MaterialX Shader Generation](https://github.com/AcademySoftwareFoundation/MaterialX/blob/main/documents/DeveloperGuide/ShaderGeneration.md)
to generate [OSL](https://github.com/AcademySoftwareFoundation/OpenShadingLanguage) source code from a [*.mtlx file](https://www.materialx.org/Specification.html).

This repo is a snippet for generating OSL and is only meant to be used for demonstrative purposes. You can read my blog
post about the project [here](https://blog.roblesch.page/2022/03/16/mtlx-to-osl.html).

The code here is a trimmed down version of the document loading workflow from [MaterialX Viewer](https://github.com/AcademySoftwareFoundation/MaterialX/blob/main/documents/DeveloperGuide/Viewer.md).
It depends on [MaterialX](https://github.com/AcademySoftwareFoundation/MaterialX) as a submodule.

Dependencies - 

```bash
git submodule update --init --recursive
```

Usage -

```bash
mtlx-to-osl [absolute-path-to-mtlx-file] [absolute-path-to-MaterialX-root] [osl-output-filename]
```
