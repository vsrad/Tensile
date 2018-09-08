/*******************************************************************************
* Copyright (C) 2016 Advanced Micro Devices, Inc. All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell cop-
* ies of the Software, and to permit persons to whom the Software is furnished
* to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IM-
* PLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
* FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
* COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
* IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNE-
* CTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*******************************************************************************/

#pragma once

#include <limits>

#define DEBUG_SM 0

// SolutionMapper:
// Efficiently map problems to exact or best solution
// Supports efficient searching and various algorithms to find
// a 'best match' from the available solutions
// This provides mappings for a single device type
template <class ProblemParmsType>
class SolutionMapper {
  // Problem to Solution mapping:
  typedef std::pair<const ProblemParmsType, int>  PtoS;

  enum Algo {PickNoneAlgo= -1, RandomAlgo= -2, RatioDistanceAlgo= -3, EuclideanDistanceAlgo= -4, ManhattanDistanceAlgo= -5};
public:
  // Runtime information for the solution:
  //   - const pointer to the info including function pointers, name, and assertion requirements
  //   - runtime information including status of the necessary code object(s) in memory
  struct SolutionRuntime {
    SolutionRuntime() : _info(nullptr) {};

    const SolutionInfo *_info;
    SolutionLock _lock;
    bool isValid() const { return _info != nullptr; };
  };

public:
  SolutionMapper(const SolutionInfo *solutionTable, size_t numSolutions,
                 const PtoS *embeddedExactTable, size_t numExacts,
                 const ProblemProperties *props)
     : _numSolutions(numSolutions), _props(props), _findAlg(EuclideanDistanceAlgo)
  {
    _solutionTable = new SolutionRuntime[numSolutions];

    for (size_t i=0; i<numSolutions; i++) {
      _solutionTable[i]._info = &solutionTable[i];
    }

    for (size_t i=0; i<numExacts; i++) {
      auto &p = embeddedExactTable[i].first;  //problem
      auto solutionIdx = embeddedExactTable[i].second;
      auto const &solution = solutionTable[solutionIdx];

      if (AssertionProperties(p,props).validForSolution(solution._assertions)) {
        _exactVector.push_back(embeddedExactTable[i]);
        _exactMap.insert({p, solutionIdx});
      } else {
        // TODO - ideally these should never make it into the exact table in the first place,
        if (DEBUG_SM)
          std::cout << "warning: removing bogus exact problem (does not meet assertion requirements for solution)\n";
      }
    }

    const char *alg = std::getenv("TENSILE_FIND_ALGO"); //See Algo or >=0 specified specific solution
    if (alg) {
      _findAlg = strtol(alg,nullptr,0);
    }
    if (DEBUG_SM & 0x1)
      printf ("TENSILE_FIND_ALGO= %d (%s)\n", _findAlg, algoString(_findAlg));
  }

#define CASE_STRING(X)  case X: return(#X)
  const char *algoString(int algo) o
  {
    if (algo >= 0) {
      return "Explicitly-Selected";
    }
    switch (algo) {
      CASE_STRING(PickNoneAlgo);
      CASE_STRING(RandomAlgo);
      CASE_STRING(RatioDistanceAlgo);
      CASE_STRING(EuclideanDistanceAlgo);
      CASE_STRING(ManhattanDistanceAlgo);
      default: return ("Unknown Algo");
    };
  };

  // Returns integer solutionIdx if exact match is found else -1
  int findExactMatch(const ProblemParmsType &p) const
  {
    auto fiter = _exactMap.find(p);
    if (fiter != _exactMap.end()) {
      return fiter->second;
    } else {
      return -1;
    }
  }

  // Iterates through all known exact matching and finds the 'closest' match.
  template <class DistanceFunction>
  int findNearestMatch(const ProblemParmsType &p, DistanceFunction distanceF) const
  {
    AssertionProperties pa(p,_props);

    auto bestIter = _exactVector.end();
    double bestDistance = std::numeric_limits<double>::max();

    for (auto iter = _exactVector.begin(); iter != _exactVector.end(); iter++) {
      auto tableP = iter->first;
      auto solutionInfo= getSolution(iter->second)._info;
      if (pa.validForSolution(solutionInfo->_assertions)) {
        double distance = distanceF(p, tableP);
        if (DEBUG_SM & 0x2)
          iter->first.print(std::cout);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIter = iter;
          if (DEBUG_SM & 0x2)
            std::cout << " distance=" << distance << " **newBest**" << "\n";
        } else {
          //std::cout << " distance=" << distance << "\n";
        }
      }
    }

    if (bestIter != _exactVector.end())
      return bestIter->second;
    else
      return -1; // if no solutions in the table
  };

  int findNearestMatchWithAlg(const ProblemParmsType &p) const
  {
    if (_findAlg >= 0) {
      if (_findAlg < _numSolutions) {
        return _findAlg; // user specified a specific algorithm
      }
    }
    switch (_findAlg) {
      case PickNoneAlgo: // Fall through to range logic
        return -1;
      case RandomAlgo:
        return findNearestMatch (p, RandomDistance<decltype(p)>());
      case EuclideanDistanceAlgo:
        return findNearestMatch (p, EuclideanDistance<decltype(p)>());
      case ManhattanDistanceAlgo:
        return findNearestMatch (p, ManhattanDistance<decltype(p)>());
      case RatioDistanceAlgo:
      default:
        return findNearestMatch (p, RatioDistance<decltype(p)>());
        break;
    }

    return -1;
  }

  // For the specified matrix dimensions, find a best-fit GEMM kernel
  // This routine does perform any auto-tuning or benchmarking
  int findAlgorithmStatic(const ProblemParmsType &p)
  {
    std::lock_guard<std::mutex> lockGuard(_cachedMutex);
    auto fiter = _cachedLookups.find(p);
    if (fiter != _cachedLookups.end()) {
      if (DEBUG_SM)
        std::cout << "findAlgorithmStatic hit in cache, " << fiter->second << "\n";
      return fiter->second;

    } else {
      // Less frequently come here, this is only first time problem size is seen.
      int solutionIdx = findExactMatch(p);
      if (solutionIdx == -1) {
        solutionIdx = findNearestMatchWithAlg (p);
        if (DEBUG_SM)
          std::cout << "findAlgorithmStatic picked nearest-match solutionIdx=" << solutionIdx << "\n";
      } else {
        if (DEBUG_SM)
          std::cout << "findAlgorithmStatic picked exact solutionIdx=" << solutionIdx << "\n";
      }

      // Save problem->solutionIdx mapping so future lookups are fast:
      _cachedLookups.insert({p, solutionIdx});

      return solutionIdx;
    }
  }


  const SolutionRuntime &getSolution(int solutionIdx) const { return _solutionTable[solutionIdx]; };

private:
  SolutionRuntime         *_solutionTable;
  size_t                      _numSolutions;

  const ProblemProperties *_props;

  // Two different structures supporting mapping from problems to solutions:
  // Map for fast exact lookups and a vector for fast walking
  std::map<const ProblemParmsType, int> _exactMap;
  std::vector<PtoS>                     _exactVector;

  std::mutex                            _cachedMutex;
  std::map<const ProblemParmsType, int> _cachedLookups;

  int                    _findAlg;
};

#if 0
// Maps from device to appropriate solution
class GlobalSolutionMapper
{
  GlobalSolutionMapper()  {
  };

  private:
  std::vector <SolutionMapper*>
};
#endif




