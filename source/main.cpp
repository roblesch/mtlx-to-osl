#include "MaterialXCore/Document.h"
#include "MaterialXFormat/File.h"
#include "MaterialXFormat/XmlIo.h"
#include "MaterialXGenShader/GenContext.h"
#include "MaterialXGenShader/Util.h"
#include "MaterialXGenOsl/OslShaderGenerator.h"
#include "MaterialXGenGlsl/GlslShaderGenerator.h"
#include "MaterialXRender/Util.h"
#include "MaterialXFormat/Util.h"
#include "MaterialXGenShader/DefaultColorManagementSystem.h"
#include "MaterialXRender/ShaderRenderer.h"

#include <iostream>
#include <string>
#include <fstream>


namespace mx = MaterialX;


void writeTextFile(const std::string& text, const std::string& filePath)
{

}

int main(int argc, char *argv[]) {

    if (argc != 4) {
        std::cerr << "usage: mtlx-to-osl [absolute-path-to-mtlx-file] [absolute-path-to-mtlx-libs] [osl-outfile-name]" << std::endl;
        exit(EXIT_FAILURE);
    }

    mx::FilePath materialFilename(argv[1]);
    mx::FileSearchPath searchPath(argv[2]);
    mx::FilePath oslFilename = argv[3];

    std::cout << '\n' << materialFilename.asString()
              << '\n' << oslFilename.asString()
              << '\n' << std::endl;

    /* === BEGIN LOAD STD LIB */
    // Load standard libraries
    mx::FilePathVec libraryFolders = { "libraries" };
    mx::DocumentPtr stdLib;
    mx::StringSet xincludeFiles;
    try {
        stdLib = mx::createDocument();
        xincludeFiles = mx::loadLibraries(libraryFolders, searchPath, stdLib);
        if (xincludeFiles.empty()) {
            std::cerr << "Could not find standard data libraries on the given search path: " << searchPath.asString()
                      << std::endl;
        }
    }
    catch (std::exception& e)
    {
        std::cerr << "Failed to load standard data libraries: " << e.what() << std::endl;
        exit(EXIT_FAILURE);
    }

    // Initialize unit management
    mx::UnitConverterRegistryPtr unitRegistry(mx::UnitConverterRegistry::create());
    mx::LinearUnitConverterPtr distanceUnitConverter;
    mx::StringVec distanceUnitOptions;

    mx::UnitTypeDefPtr distanceTypeDef = stdLib->getUnitTypeDef("distance");
    distanceUnitConverter = mx::LinearUnitConverter::create(distanceTypeDef);
    unitRegistry->addUnitConverter(distanceTypeDef, distanceUnitConverter);
    mx::UnitTypeDefPtr angleTypeDef = stdLib->getUnitTypeDef("angle");
    mx::LinearUnitConverterPtr angleConverter = mx::LinearUnitConverter::create(angleTypeDef);
    unitRegistry->addUnitConverter(angleTypeDef, angleConverter);

    // Create the list of supported distance units
    auto unitScales = distanceUnitConverter->getUnitScale();
    distanceUnitOptions.resize(unitScales.size());
    for (auto unitScale : unitScales)
    {
        int location = distanceUnitConverter->getUnitAsInteger(unitScale.first);
        distanceUnitOptions[location] = unitScale.first;
    }

    // Initialize generator context
    mx::GenContext context(mx::OslShaderGenerator::create());
    context.getOptions().targetColorSpaceOverride = "lin_rec709";
    context.getOptions().fileTextureVerticalFlip = false;

    for (const mx::FilePath& path : searchPath)
    {
        context.registerSourceCodeSearchPath(path / "libraries");
    }

    // Initialize color management.
    mx::DefaultColorManagementSystemPtr cms = mx::DefaultColorManagementSystem::create(context.getShaderGenerator().getTarget());
    cms->loadLibrary(stdLib);
    context.getShaderGenerator().setColorManagementSystem(cms);

    // Initialize unit management.
    mx::UnitSystemPtr unitSystem = mx::UnitSystem::create(context.getShaderGenerator().getTarget());
    unitSystem->loadLibrary(stdLib);
    unitSystem->setUnitConverterRegistry(unitRegistry);
    context.getShaderGenerator().setUnitSystem(unitSystem);
    context.getOptions().targetDistanceUnit = "meter";
    /* === END LOAD STD LIB */

    /* === BEGIN LOAD DOCUMENT */
    // Set up read options.
    mx::XmlReadOptions readOptions;
    readOptions.readXIncludeFunction = [](mx::DocumentPtr doc, const mx::FilePath& filename,
                                          const mx::FileSearchPath& searchPath, const mx::XmlReadOptions* options)
    {
        mx::FilePath resolvedFilename = searchPath.find(filename);
        if (resolvedFilename.exists())
        {
            readFromXmlFile(doc, resolvedFilename, searchPath, options);
        }
        else
        {
            std::cerr << "Include file not found: " << filename.asString() << std::endl;
        }
    };

    try
    {
        // Load material document
        mx::DocumentPtr doc = mx::createDocument();
        mx::readFromXmlFile(doc, materialFilename, searchPath, &readOptions);

        // Import libraries
        doc->importLibrary(stdLib);

        // Validate the document
        std::string message;
        if (!doc->validate(&message))
        {
            std::cerr << "*** Validation warnings for " << materialFilename.getBaseName() << " ***" << std::endl;
            std::cerr << message;
        }

        // Find new renderable elements.
        mx::StringVec renderablePaths;
        std::vector<mx::TypedElementPtr> docElems;
        std::vector<mx::NodePtr> materialNodes;
        mx::findRenderableElements(doc, docElems);
        if (docElems.empty())
        {
            throw mx::Exception("No renderable elements found in " + materialFilename.getBaseName());
        }
        auto docElem = docElems.front();
        mx::TypedElementPtr renderableElem = docElem;
        mx::NodePtr node = docElem->asA<mx::Node>();
        if (node && node->getType() == mx::MATERIAL_TYPE_STRING)
        {
            std::vector<mx::NodePtr> shaderNodes = getShaderNodes(node);
            if (!shaderNodes.empty())
            {
                renderableElem = shaderNodes[0];
            }
            materialNodes.push_back(node);
        }
        else
        {
            materialNodes.push_back(nullptr);
        }
        auto renderablePath = renderableElem->getNamePath();
        mx::ElementPtr elemptr = doc->getDescendant(renderablePath);
        mx::TypedElementPtr typedElem = elemptr ? elemptr->asA<mx::TypedElement>() : nullptr;

        // Create shader
        const bool hasTransparency = mx::isTransparentSurface(typedElem, context.getShaderGenerator().getTarget());
        mx::GenContext materialContext = context;
        materialContext.getOptions().hwTransparency = hasTransparency;
        mx::ShaderPtr shader = createShader(typedElem->getNamePath(), materialContext, typedElem);
        const std::string& pixelShader = shader->getSourceCode(mx::Stage::PIXEL);
        std::ofstream file;
        file.open("pixelShader.osl");
        file << pixelShader;
        file.close();
    }
    catch (mx::ExceptionRenderError& e)
    {
        for (const std::string& error : e.errorLog())
        {
            std::cerr << error << std::endl;
            exit(EXIT_FAILURE);
        }
    }
    catch (std::exception& e)
    {
        std::cerr << "Failed to load material: " << e.what() << std::endl;
        exit(EXIT_FAILURE);
    }

    return 99;

    /*
    std::vector<MaterialPtr> newMaterials;
    try
    {
        // Load material document
        mx::DocumentPtr doc = mx::createDocument();
        mx::readFromXmlFile(doc, materialFilename, searchPath, &readOptions);

        // Import libraries
        doc->importLibrary(stdLib);

        // Validate the document
        std::string message;
        if (!doc->validate(&message))
        {
            std::cerr << "*** Validation warnings for " << materialFilename.getBaseName() << " ***" << std::endl;
            std::cerr << message;
        }
        // Find new renderable elements.
        mx::StringVec renderablePaths;
        std::vector<mx::TypedElementPtr> elems;
        std::vector<mx::NodePtr> materialNodes;
        mx::findRenderableElements(doc, elems);
        if (elems.empty())
        {
            throw mx::Exception("No renderable elements found in " + materialFilename.getBaseName());
        }
        for (mx::TypedElementPtr elem : elems)
        {
            mx::TypedElementPtr renderableElem = elem;
            mx::NodePtr node = elem->asA<mx::Node>();
            if (node && node->getType() == mx::MATERIAL_TYPE_STRING)
            {
                std::vector<mx::NodePtr> shaderNodes = getShaderNodes(node);
                if (!shaderNodes.empty())
                {
                    renderableElem = shaderNodes[0];
                }
                materialNodes.push_back(node);
            }
            else
            {
                materialNodes.push_back(nullptr);
            }
            renderablePaths.push_back(renderableElem->getNamePath());
        }

        // Check for any udim set.
        mx::ValuePtr udimSetValue = doc->getGeomPropValue("udimset");

        // Create new materials.
        mx::TypedElementPtr udimElement;
        for (size_t i=0; i<renderablePaths.size(); i++)
        {
            const auto& renderablePath = renderablePaths[i];
            mx::ElementPtr elem = doc->getDescendant(renderablePath);
            mx::TypedElementPtr typedElem = elem ? elem->asA<mx::TypedElement>() : nullptr;
            if (!typedElem)
            {
                continue;
            }
            if (udimSetValue && udimSetValue->isA<mx::StringVec>())
            {
                for (const std::string& udim : udimSetValue->asA<mx::StringVec>())
                {
                    MaterialPtr mat = Material::create();
                    mat->setDocument(doc);
                    mat->setElement(typedElem);
                    mat->setMaterialNode(materialNodes[i]);
                    mat->setUdim(udim);
                    newMaterials.push_back(mat);

                    udimElement = typedElem;
                }
            }
            else
            {
                MaterialPtr mat = Material::create();
                mat->setDocument(doc);
                mat->setElement(typedElem);
                mat->setMaterialNode(materialNodes[i]);
                newMaterials.push_back(mat);
            }
        }
        if (!newMaterials.empty()) {
            for (MaterialPtr mat : newMaterials) {
                mx::TypedElementPtr elem = mat->getElement();
                mat->generateShader(context);
            }
        }
    }
    catch (mx::ExceptionRenderError& e)
    {
        for (const std::string& error : e.errorLog())
        {
            std::cerr << error << std::endl;
            exit(EXIT_FAILURE);
        }
    }
    catch (std::exception& e)
    {
        std::cerr << "Failed to load material: " << e.what() << std::endl;
        exit(EXIT_FAILURE);
    }*/

    // Load material document
//    mx::DocumentPtr doc = mx::createDocument();
//    mx::readFromXmlFile(doc, materialFilename);
//
//    // Validate document
//    std::string message;
//    if (!doc->validate(&message))
//    {
//        std::cerr << "*** Validation warnings for " << materialFilename.getBaseName() << " ***" << std::endl;
//        std::cerr << message;
//    }
//
//    // Get renderable element
//    std::vector<mx::TypedElementPtr> elems;
//    mx::findRenderableElements(doc, elems);
//    if (elems.empty())
//    {
//        std::cerr << "No renderable elements found in " + materialFilename.getBaseName() << std::endl;
//        exit(EXIT_FAILURE);
//    }
//    auto elem = elems.front();
//
//    // Configure shader gen context
//
//    // init
//    mx::GenContext genContextOsl(mx::OslShaderGenerator::create());
//    genContextOsl.getOptions().targetColorSpaceOverride = "lin_rec709";
//    genContextOsl.getOptions().fileTextureVerticalFlip = false;

//    bool hasTransparency = mx::isTransparentSurface(elem, genContextOsl.getShaderGenerator().getTarget());
//    mx::GenContext materialContext = genContextOsl;
//    materialContext.getOptions().hwTransparency = hasTransparency;
//
//    auto hwShader = createShader("Shader", materialContext, elem);
//    if (!hwShader)
//    {
//        return false;
//    }


}
