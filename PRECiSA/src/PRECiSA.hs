-- Notices:
--
-- Copyright 2020 United States Government as represented by the Administrator of the National Aeronautics and Space Administration. All Rights Reserved.

-- Disclaimers
-- No Warranty: THE SUBJECT SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY OF ANY KIND, EITHER EXPRESSED, IMPLIED, OR STATUTORY, INCLUDING, BUT NOT LIMITED TO, ANY WARRANTY THAT THE SUBJECT SOFTWARE WILL CONFORM TO SPECIFICATIONS, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR FREEDOM FROM INFRINGEMENT, ANY WARRANTY THAT THE SUBJECT SOFTWARE WILL BE ERROR FREE, OR ANY WARRANTY THAT DOCUMENTATION, IF PROVIDED, WILL CONFORM TO THE SUBJECT SOFTWARE. THIS AGREEMENT DOES NOT, IN ANY MANNER, CONSTITUTE AN ENDORSEMENT BY GOVERNMENT AGENCY OR ANY PRIOR RECIPIENT OF ANY RESULTS, RESULTING DESIGNS, HARDWARE, SOFTWARE PRODUCTS OR ANY OTHER APPLICATIONS RESULTING FROM USE OF THE SUBJECT SOFTWARE.  FURTHER, GOVERNMENT AGENCY DISCLAIMS ALL WARRANTIES AND LIABILITIES REGARDING THIRD-PARTY SOFTWARE, IF PRESENT IN THE ORIGINAL SOFTWARE, AND DISTRIBUTES IT "AS IS."

-- Waiver and Indemnity:  RECIPIENT AGREES TO WAIVE ANY AND ALL CLAIMS AGAINST THE UNITED STATES GOVERNMENT, ITS CONTRACTORS AND SUBCONTRACTORS, AS WELL AS ANY PRIOR RECIPIENT.  IF RECIPIENT'S USE OF THE SUBJECT SOFTWARE RESULTS IN ANY LIABILITIES, DEMANDS, DAMAGES, EXPENSES OR LOSSES ARISING FROM SUCH USE, INCLUDING ANY DAMAGES FROM PRODUCTS BASED ON, OR RESULTING FROM, RECIPIENT'S USE OF THE SUBJECT SOFTWARE, RECIPIENT SHALL INDEMNIFY AND HOLD HARMLESS THE UNITED STATES GOVERNMENT, ITS CONTRACTORS AND SUBCONTRACTORS, AS WELL AS ANY PRIOR RECIPIENT, TO THE EXTENT PERMITTED BY LAW.  RECIPIENT'S SOLE REMEDY FOR ANY SUCH MATTER SHALL BE THE IMMEDIATE, UNILATERAL TERMINATION OF THIS AGREEMENT.


{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}

module PRECiSA
  ( main,
    computeAllErrorsInKodiak,
  )
where

import AbsPVSLang
import AbsSpecLang
import AbstractSemantics
import AbstractDomain
import Common.DecisionPath
import Common.ControlFlow
import Control.Monad.Except
import Data.Maybe (fromMaybe,fromJust)
import ErrM
import FPCore.FPCorePrinter
import PVSTypes
import Options
import PPExt
import Kodiak.Runner
import Kodiak.Runnable
import MapFPCoreLangAST
import qualified Kodiak.Paver as KP
import Prelude hiding ((<>))
import PVSCert
import Parser.Parser
import SMT.SMT
import System.Directory
import System.FilePath
import Translation.Float2Real
import Debug.Trace

main :: IO ()
main = parseOptions >>= parseAndAnalyze

initDpsToNone :: Decl -> (FunName, [LDecisionPath])
initDpsToNone (Decl _ _ f _ _) = (f,[])
initDpsToNone (Pred _ _ f _ _) = (f,[])

initDpsToAll :: Decl -> (FunName, [LDecisionPath])
initDpsToAll (Decl _ _ f _ _) = (f,[root])
initDpsToAll (Pred _ _ f _ _) = (f,[root])

renderPVS :: Doc -> String
renderPVS = renderStyle Style{mode = LeftMode, lineLength = 80, ribbonsPerLine = 2.0}

parseAndAnalyze :: Options -> IO ()
parseAndAnalyze
  Options
          { optProgramFile          = fileprog
          , optInputRangeFile       = filespec
          , optPathFile             = filedps
          , optParseFPCore          = parsefpcore
          , optParseFPCoreSpec      = parsefpcorespec
          , optPrintFPCore          = printfpcore
          , optImproveError         = impErr
          , optWithPaving           = withPaving
          , optMaxDepth             = maxBBDepth
          , optPrecision            = prec
          , optMaxNumLemma          = maxel
          , optNoCollapsedStables   = noCollapsedStables
          , optAssumeStability      = sta
          , optNoCollapsedUnstables = notMu
          , optSMTOptimization      = useSMT } = do
  errparseProg <- if parsefpcore
                  then do
                    parseFileToFPCoreProgram fileprog
                  else do
                    parseFileToProgram fileprog
  decls <- errify error errparseProg
  spec <- if parsefpcorespec
          then do
            if parsefpcore
            then
              parseFileToFPCoreSpec fileprog
            else
              error $ "Cannot parse FPCore as spec unless also parsed as program"
          else do
            errparseSpec <- parseFileToSpec decls filespec
            errify fail errparseSpec
  dps <- if noCollapsedStables
         then return $ map initDpsToAll decls
         else if null filedps
         then return $ map initDpsToNone decls
         else do
           errparseTargetDPs <- parseFileToTargetDPs filedps
           errify fail errparseTargetDPs

  -------------
  let progSem = fixpointSemantics decls (botInterp decls) 3 semConf dps
  checkProgSize progSem 0 maxel
  let symbCertificates = renderPVS $ genCertFile inputFileName certFileName realProgFileName decls progSem
  writeFile certFile symbCertificates
  let realProgDoc = genRealProgFile inputFileName  realProgFileName (fp2realProg decls)
  writeFile realProgFile (renderPVS realProgDoc)
  -------------- just for batch mode
  putStrLn "********************************************************************"
  putStrLn "****************************** PRECiSA *****************************"
  putStrLn ""
  let searchParams = KP.SP { maximumDepth = fromInteger . toInteger $ maxBBDepth
                           , minimumPrecision = fromInteger . toInteger $ prec }
  let pgmSemUlp = removeInfiniteCebS progSem

  filteredPgmSemUlp <- if useSMT
    then do createDirectoryIfMissing True filePathSMT
            filterUnsatCebs (KP.maximumDepth searchParams) (KP.minimumPrecision searchParams) filePathSMT pgmSemUlp spec
    else return pgmSemUlp

  let unfoldedPgmSem = unfoldSemantics filteredPgmSemUlp
  results <- computeAllErrorsInKodiak unfoldedPgmSem spec searchParams
  let resultSummary = summarizeAllErrors (getKodiakResults results)
  printAllErrors resultSummary
  let numCertificate = renderPVS $ genNumCertFile certFileName numCertFileName results decls spec maxBBDepth prec False
  writeFile numCertFile numCertificate
  if printfpcore
  then do putStrLn $ renderPVS $ fpcprintProgram decls spec
  else return ()
  putStrLn ""
  -------------- just for batch mode
  putStrLn "********************************************************************"
  putStrLn "***** Files generated successfully *****"
  putStrLn ("Symbolic lemmas and proofs in: " ++ certFile)
  putStrLn ("Numeric lemmas and proofs in: " ++ numCertFile)
  pavingFiles <- if withPaving
  then do
    let unstableCondInterp = map (\(fun, (_,_,_,sem)) -> (fun, map conds (filter isUnstable sem))) unfoldedPgmSem
    let kodiakFunConds = map (\(f,conditions) -> (f,fromMaybe (error "kodiakFunConds") (KP.conds2Kodiak' conditions))) unstableCondInterp
    KP.paveUnstabilityConditions kodiakFunConds spec searchParams (generatePavingFilename (filePath++inputFileName))
  else return []
  when withPaving $
      mapM_ (\(fun,file) -> putStrLn $ "Paving for function " ++ fun ++ " generated in: " ++ file) pavingFiles
    where
      mu = not notMu
      semConf = SemConf {improveError = impErr, assumeTestStability = sta, mergeUnstables = mu}
      inputFileName = takeBaseName fileprog
      filePath = dropFileName fileprog
      filePathSMT = filePath ++ inputFileName ++ "_SMT/"
      certFile =  filePath ++ certFileName ++ ".pvs"
      numCertFile = filePath ++ numCertFileName ++ ".pvs"
      realProgFile = filePath ++ inputFileName ++ "_real.pvs"
      certFileName = inputFileName ++ "_cert"
      numCertFileName = inputFileName ++ "_num_cert"
      realProgFileName = inputFileName ++ "_real"
      generatePavingFilename pvsFilename functionName = pvsFilename ++ "." ++ functionName ++ ".paving"

getKodiakResults :: [(String,PVSType,[Arg],[(Conditions, LDecisionPath,ControlFlow,KodiakResult,AExpr,[FAExpr],[AExpr])])] -> [(String, [(ControlFlow,KodiakResult)])]
getKodiakResults = map getKodiakResult
  where
     getKodiakResult (f,_,_,errors) = (f, map getKodiakError errors)
     getKodiakError (_,_,cf,err,_,_,_) = (cf,err)

summarizeAllErrors :: [(String, [(ControlFlow, KodiakResult)])] -> [(String, [(ControlFlow, Double)])]
summarizeAllErrors errorMap = map aux errorMap
  where
    aux (f, results) =
      let stableCases = filter ((== Stable) . fst) results in
      let unstableCases = filter ((== Unstable) . fst) results in
      (f,[(Stable,maximum $ map (maximumUpperBound . snd) stableCases)]
         ++
         if null unstableCases then []
         else [(Unstable, maximum $ map (maximumUpperBound . snd) unstableCases)])

printAllErrors :: [(String,[(ControlFlow,Double)])] -> IO ()
printAllErrors = mapM_ printFunction
  where
    printFunction (f,results) = do
      putStrLn $ "Function " ++ f
      mapM_ printRes results
    printRes (flow, err) = do
      if flow == Stable
        then putStrLn $ "  stable paths: " ++ render (prettyNumError $ err)
        else putStrLn $ "  unstable paths: " ++ render (prettyNumError $ err)

computeAllErrorsInKodiak :: Interpretation
                         -> Spec
                         -> KP.SearchParameters
                         -> IO [(String,PVSType,[Arg],[(Conditions, LDecisionPath,ControlFlow,KodiakResult,AExpr,[FAExpr],[AExpr])])]
computeAllErrorsInKodiak interp (Spec specBinds) searchParams = mapM runFunction functionNames
  where
    declInterps = filter isDeclInterp interp
    functionNames = map fst declInterps
    functionBindingsMap = map (\(SpecBind f b) -> (f,b)) specBinds
    functionErrorExpressionsMap = map toPathFlowErrorTuple declInterps
      where
        toPathFlowErrorTuple (f,(_,fp,args,acebs)) = (f,map (\x -> (fp,args,aceb2PathFlowErrorTuple x)) acebs)
          where
            aceb2PathFlowErrorTuple aceb = (conds aceb, decisionPath aceb, cFlow aceb,
              fromJust $ eExpr aceb, fDeclRes $ fpExprs aceb, rDeclRes $ rExprs aceb)

    runFunction fname = do
      results <- mapM runErrorExpression $
                  fromMaybe (error $ "runFunction: function " ++ show fname ++ " not found in input bound specification.")
                            (lookup fname functionErrorExpressionsMap)
      let (fprec,args,_):_ = results
      let results' = map (\(_,_,a) -> a) results
      return (fname, fprec, args, results')
      where
        runErrorExpression (fprec :: PVSType,args :: [Arg],(conditions :: Conditions,path :: LDecisionPath, flow, err, fpes, res)) = do
          result <- run kodiakInput ()
          return (fprec, args, (conditions, path, flow, result, initAExpr err, fpes, res))
            where
              kodiakInput = KI { kiName = fname,
                                 kiExpression = simplAExpr $ initAExpr err,
                                 kiBindings = fromMaybe (error $ "runFunction: function " ++ show fname ++ " not found.")
                                                      (lookup fname functionBindingsMap),
                                 kiMaxDepth  = KP.maximumDepth searchParams,
                                 kiPrecision = KP.minimumPrecision searchParams
                               }
